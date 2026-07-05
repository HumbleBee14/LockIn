import Foundation

// what the engine should currently be enforcing — compared tick-to-tick so we re-apply only on real change
enum EngineDesire: Equatable {
    case clear
    case block(domains: Set<String>, allowlist: Bool, expand: Bool)
    case unknown   // engine state unverified (a write failed) — never equals `want`, so the next tick re-applies
}

// invariant: main-actor isolated so the timer loop and XPC handlers can't race on lock state
@MainActor
public final class BlockController {
    private let snapshotStore: LockSnapshotStore
    private let configStore: ConfigStore
    private let appBlocker: AppBlocking
    private let blocker: WebsiteBlocker
    private let nowProvider: NowProvider
    private var appliedSnapshotIds: Set<String> = []

    init(snapshotStore: LockSnapshotStore, configStore: ConfigStore = .shared,
         appBlocker: AppBlocking = AppBlocker(), blocker: WebsiteBlocker = WebsiteBlocker(),
         nowProvider: NowProvider = SystemNowProvider(trusted: TrustedTime.system())) {
        self.snapshotStore = snapshotStore
        self.configStore = configStore
        self.appBlocker = appBlocker
        self.blocker = blocker
        self.nowProvider = nowProvider
    }

    public static func makeSystemController() -> BlockController {
        BlockController(snapshotStore: LockSnapshotStore(
            path: URL(fileURLWithPath: "/Library/Application Support/LockIn/active.plist")))
    }

    private func now() -> Date { nowProvider.now() }

    func registerSchedule(_ config: ScheduleConfig) -> Bool {
        // invariant: never mutate an active snapshot; edits affect only rules not yet started
        try? configStore.save(config)
        return true
    }

    // shared merge/dedup/cap used by quick lock and scheduled snapshots so their logic can't diverge
    struct ResolvedBlock {
        let domains: [String]
        let apps: [String]
        let isAllowlist: Bool
        let primaryId: String
        let title: String
    }

    func resolveSets(_ blockSetIds: [String], in config: ScheduleConfig) -> ResolvedBlock? {
        let sets = blockSetIds.compactMap { id in config.blockSets.first { $0.id == id } }
        guard let first = sets.first else { return nil }
        // all selected sets must share one mode; mixing allow/block is rejected
        guard sets.allSatisfy({ $0.mode == first.mode }) else { return nil }

        var domains: [String] = []
        var apps: [String] = []
        var seenD = Set<String>(), seenA = Set<String>()
        for set in sets {
            // invariant: drop any domain with control chars/whitespace/markers before it reaches /etc/hosts
            for d in set.domains where Self.isSafeDomain(d) && seenD.insert(d).inserted { domains.append(d) }
            for a in set.appBundleIds where seenA.insert(a).inserted { apps.append(a) }
        }
        guard !domains.isEmpty else { return nil }
        // invariant: never silently truncate — an over-cap set is a surfaced failure, not a partial block
        guard domains.count <= BlockLimits.maxActiveDomains else { return nil }
        let title = sets.count == 1 ? first.name : "\(first.name) +\(sets.count - 1)"
        return ResolvedBlock(domains: domains, apps: apps,
                             isAllowlist: first.mode == .allowlist, primaryId: first.id, title: title)
    }

    private func domainCount(_ blockSetIds: [String], in config: ScheduleConfig) -> Int {
        var seen = Set<String>()
        for id in blockSetIds {
            for d in config.blockSets.first(where: { $0.id == id })?.domains ?? []
            where Self.isSafeDomain(d) { seen.insert(d) }
        }
        return seen.count
    }

    static func isSafeDomain(_ d: String) -> Bool {
        guard !d.isEmpty, d.count <= 253 else { return false }
        if d.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return false }
        if d.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return false }
        if d.contains("#") { return false }
        return true
    }

    func startQuickLock(blockSetIds: [String], durationSeconds: Double) -> Bool {
        startQuickLockReason(blockSetIds: blockSetIds, durationSeconds: durationSeconds) == nil
    }

    // nil on success; otherwise a short reason for the failure so the app can show it
    func startQuickLockReason(blockSetIds: [String], durationSeconds: Double) -> String? {
        let existing = snapshotStore.load()
        let config = persistedConfig()
        if existing.count >= BlockLimits.maxActiveLocks {
            return "Too many locks are active (max \(BlockLimits.maxActiveLocks)). Wait for one to end."
        }
        if domainCount(blockSetIds, in: config) > BlockLimits.maxActiveDomains {
            return "This block set is too large (over \(BlockLimits.maxActiveDomains) sites). Split it into smaller sets."
        }
        guard let r = resolveSets(blockSetIds, in: config) else {
            return "No valid sites to block (the selected sets are empty or mix allow/block modes)."
        }
        // invariant (Law 3): while anything is locked, a new lock may only shrink reachability
        if !existing.isEmpty && r.isAllowlist {
            return "Only blocklist locks can be added while a lock is active."
        }
        if Set(existing.flatMap(\.appliedDomains) + r.domains).count > BlockLimits.maxActiveDomains {
            return "This would exceed the maximum of \(BlockLimits.maxActiveDomains) blocked sites."
        }
        let snap = freshSnapshot(id: "quick-" + UUID().uuidString, mode: .adHoc,
                                 endsAt: now().addingTimeInterval(durationSeconds),
                                 r: r, settings: config.settings)
        let combined = existing + [snap]
        let e = EffectiveBlock.resolve(combined)
        let expand = EffectiveBlock.effectiveExpand(combined)
        // synchronous to this XPC reply, but ordered on the serial engine queue (never interleaves a tick apply)
        let applied = blocker.applyAndWait(domains: e.domains, allowlist: e.isAllowlist, expandSubdomains: expand)
        guard applied else {
            restorePreviousUnion(existing)
            return "Block not applied at the system level. Lock aborted."
        }
        desiredEngine = .block(domains: Set(e.domains), allowlist: e.isAllowlist, expand: expand)
        engineDegraded = false
        try? snapshotStore.save(combined)
        appliedSnapshotIds = Set(combined.map { $0.id })
        pushAppUnion(combined)
        return nil
    }

    // D1b: a failed forward apply may already have stripped the old union from live hosts —
    // restore it verified; if that also fails, mark degraded and let every tick retry (.unknown)
    private func restorePreviousUnion(_ existing: [LockSnapshot]) {
        guard !existing.isEmpty else {
            desiredEngine = .clear
            blocker.clearAsync()
            return
        }
        let prev = EffectiveBlock.resolve(existing)
        let expand = EffectiveBlock.effectiveExpand(existing)
        let restored = blocker.applyAndWait(domains: prev.domains, allowlist: prev.isAllowlist, expandSubdomains: expand)
        engineDegraded = !restored
        desiredEngine = restored
            ? .block(domains: Set(prev.domains), allowlist: prev.isAllowlist, expand: expand)
            : .unknown
    }

    // append-only, blocklist-only (the one change allowed mid-lock). nil = success, else surfaced reason.
    func appendDomainsToActiveBlockReason(_ domains: [String]) -> String? {
        var snaps = snapshotStore.load()
        // target = the blocklist snapshot that lives longest, so an added site stays blocked to the very end
        guard let i = snaps.indices.filter({ !snaps[$0].isAllowlist })
                .max(by: { snaps[$0].endsAt < snaps[$1].endsAt }) else {
            return "No blocklist lock is active."
        }
        let existing = Set(snaps[i].appliedDomains)
        // invariant: same control-char/marker rejection as resolveSets — never write a raw XPC string to /etc/hosts
        let fresh = domains.filter { Self.isSafeDomain($0) && !existing.contains($0) }
        guard !fresh.isEmpty else { return nil }   // filtered/no-op success, never a raw write
        guard snaps[i].appliedDomains.count + fresh.count <= BlockLimits.maxActiveDomains else {
            return "This lock already holds the maximum of \(BlockLimits.maxActiveDomains) sites."
        }
        guard Set(snaps.flatMap(\.appliedDomains) + fresh).count <= BlockLimits.maxActiveDomains else {
            return "This would exceed the maximum of \(BlockLimits.maxActiveDomains) blocked sites."
        }
        var mutated = snaps
        mutated[i].appliedDomains.append(contentsOf: fresh)
        let expand = EffectiveBlock.effectiveExpand(mutated)
        if mutated.contains(where: { $0.isAllowlist }) {
            // mixed mode: BlockManager's append no-ops for allowlists — re-apply the full effective
            // union (D2 subtracts the new domain's expansion), so the site is unreachable immediately
            let e = EffectiveBlock.resolve(mutated)
            guard blocker.applyAndWait(domains: e.domains, allowlist: true, expandSubdomains: expand) else {
                restorePreviousUnion(snaps)
                return "Block not applied at the system level."
            }
            desiredEngine = .block(domains: Set(e.domains), allowlist: true, expand: expand)
        } else {
            // invariant: only record the domains in the snapshot once hosts actually carries them
            guard blocker.appendAndWait(newDomains: fresh, expandSubdomains: expand) else {
                return "Block not applied at the system level."
            }
            let e = EffectiveBlock.resolve(mutated)
            desiredEngine = .block(domains: Set(e.domains), allowlist: false, expand: expand)
        }
        try? snapshotStore.save(mutated)
        return nil
    }

    func appendDomainsToActiveBlock(_ domains: [String]) -> Bool {
        appendDomainsToActiveBlockReason(domains) == nil
    }

    // the reconcile tick: drop expired (now >= endsAt), add newly-due rules, persist, then hand the engine the union
    func reconcile(calendar: Calendar = .current) {
        let nowUTC = now()
        var snaps = snapshotStore.load().filter { nowUTC < $0.endsAt }
        addNewlyDueRules(into: &snaps, calendar: calendar, nowUTC: nowUTC)
        appliedSnapshotIds = Set(snaps.map { $0.id })
        if snaps.isEmpty {
            try? snapshotStore.clear()
            pushClearedSnapshot()
        } else {
            try? snapshotStore.save(snaps)
        }
        syncEngineToDesiredState(snaps)
    }

    // invariant: the tick only declares the desired block; the engine applies it on its own serial thread.
    // the main thread never runs apply/clear, so a 70K write can't freeze the timer or XPC (the freeze bug).
    private var desiredEngine: EngineDesire = .clear

    // set when a teardown can't fully clear hosts/pf; surfaced in status so the app can prompt a manual Reset
    private var cleanupFailed = false

    // a live-lock engine write keeps failing; direction is over-block, tick retries (spec D7)
    private(set) var engineDegraded = false

    private func syncEngineToDesiredState(_ snaps: [LockSnapshot]) {
        guard let first = snaps.first else {
            // clear on transition OR whenever a live block lingers (e.g. daemon restarted on a stale hosts block)
            if desiredEngine != .clear || blocker.liveBlockPresent() {
                desiredEngine = .clear
                blocker.clearAsync { [weak self] ok in
                    Task { @MainActor in self?.cleanupFailed = !ok }
                }
            }
            return
        }
        let e = EffectiveBlock.resolve(snaps)
        let expand = EffectiveBlock.effectiveExpand(snaps)
        let want = EngineDesire.block(domains: Set(e.domains), allowlist: e.isAllowlist, expand: expand)
        // re-apply when the desired set changed, the live block drifted (tamper self-heal),
        // or a prior write failed (.unknown never equals want → built-in retry)
        let drifted = !blocker.blockIntact(domains: e.domains, allowlist: e.isAllowlist,
                                           expandSubdomains: expand)
        if want != desiredEngine || drifted {
            desiredEngine = want
            blocker.applyAsync(domains: e.domains, allowlist: e.isAllowlist,
                               expandSubdomains: expand) { [weak self] ok in
                Task { @MainActor in
                    guard let self else { return }
                    if ok { self.engineDegraded = false }
                    else {
                        // fail-closed: enforcement never weakens early; retry next tick and surface it.
                        // a late failure may stomp a fresher desiredEngine — harmless: one extra verified re-apply.
                        self.engineDegraded = true
                        self.desiredEngine = .unknown
                    }
                }
            }
        }
        pushAppUnion(snaps)
        if !e.apps.isEmpty && !appBlocker.isMonitoring() {
            appBlocker.update(active: true, bundleIds: e.apps)
        }
    }

    private func addNewlyDueRules(into snaps: inout [LockSnapshot], calendar: Calendar, nowUTC: Date) {
        // invariant: config is read ONLY to detect a NEW rule starting; never to mutate a live snapshot.
        // no engine call here — syncEngineToDesiredState applies the union once, off-thread.
        let config = loadConfig()
        for rule in config.rules {
            guard !snaps.contains(where: { $0.id == rule.id }) else { continue }
            guard let end = Scheduler.activeWindowEndPublic(rule, at: nowUTC, calendar: calendar) else { continue }
            guard let r = resolveSets(rule.blockSetIds, in: config) else { continue }
            guard r.domains.count <= BlockLimits.maxActiveDomains else { continue }
            snaps.append(freshSnapshot(id: rule.id, mode: .scheduled, endsAt: end, r: r, settings: config.settings))
        }
    }

    private func freshSnapshot(id: String, mode: BlockMode, endsAt: Date,
                               r: ResolvedBlock, settings: SettingsConfig) -> LockSnapshot {
        LockSnapshot(id: id, mode: mode, endsAt: endsAt,
            isAllowlist: r.isAllowlist, appliedDomains: r.domains, appliedAppBundleIds: r.apps,
            appliedSettings: settings, blockSetId: r.primaryId, blockSetTitle: r.title)
    }

    private func persistedConfig() -> ScheduleConfig {
        configStore.load() ?? ScheduleConfig(rules: [])
    }

    // recovery: overwrites /etc/hosts with the macOS default. it's the escape hatch when state is wrong —
    // but it is not a disguised unlock (D6): refuse while any un-expired lock exists, mutating nothing.
    // runs off-main on the engine queue so an in-flight 70K apply can't wedge it.
    func resetHostsToDefault(completion: @escaping @Sendable (Bool) -> Void) {
        // invariant (D6): reset is recovery, not an unlock — refuse while any un-expired lock exists.
        // post-expiry dirty hosts (empty/expired store, live block) stays allowed: that's the recovery case.
        if snapshotStore.load().contains(where: { now() < $0.endsAt }) { completion(false); return }
        desiredEngine = .clear
        try? snapshotStore.clear()
        blocker.resetToSystemDefaultAsync { [weak self] ok in
            Task { @MainActor in if ok { self?.cleanupFailed = false } }
            completion(ok)
        }
    }

    // root-side cleanup for uninstall: reset hosts, clear snapshots + root config. Refused while locked.
    public func prepareUninstall() -> Bool {
        if isLockHeld() { return false }
        let ok = blocker.resetToSystemDefault()
        try? snapshotStore.clear()
        try? configStore.save(ScheduleConfig(rules: []))
        return ok
    }

    // invariant: self-clean only when the app bundle is gone AND no lock is held — never tears down a live lock
    public func isOrphaned(appBundlePath: String) -> Bool {
        !FileManager.default.fileExists(atPath: appBundlePath) && !isLockHeld()
    }

    // invariant: corroborate the snapshot set against live pf/hosts so deleting active.plist can't unlock teardown
    private func isLockHeld() -> Bool {
        if !snapshotStore.load().isEmpty { return true }
        return blocker.liveBlockPresent()
    }

    public func statusDTO(calendar: Calendar = .current) -> DaemonStatus {
        let snaps = snapshotStore.load()
        guard !snaps.isEmpty else {
            // unlocked but a block still lingers ⇒ teardown didn't fully clear; tell the app to prompt a Reset
            let dirty = cleanupFailed || blocker.liveBlockPresent()
            return DaemonStatus(active: false, source: nil, blockSetTitle: nil, isAllowlist: false,
                endsAt: nil, appliedDomains: [], nextTriggerDescription: nextTriggerDescription(calendar: calendar),
                cleanupFailed: dirty)
        }
        let e = EffectiveBlock.resolve(snaps)
        let anyScheduled = snaps.contains { $0.mode == .scheduled }
        let title = snaps.count == 1 ? snaps[0].blockSetTitle : "\(snaps[0].blockSetTitle) +\(snaps.count - 1)"
        let sorted = snaps.sorted { $0.endsAt < $1.endsAt }
        let locks = sorted.map {
            ActiveLockInfo(id: $0.id, title: $0.blockSetTitle,
                           source: $0.mode == .scheduled ? "scheduled" : "quick",
                           endsAt: $0.endsAt, isAllowlist: $0.isAllowlist,
                           blockSetId: $0.blockSetId, domainCount: $0.appliedDomains.count)
        }
        let appendTarget = snaps.filter { !$0.isAllowlist }.max { $0.endsAt < $1.endsAt }?.blockSetId
        return DaemonStatus(
            active: true,
            source: anyScheduled ? "scheduled" : "quick",
            blockSetId: snaps[0].blockSetId,
            blockSetTitle: title,
            isAllowlist: e.isAllowlist,
            endsAt: latestEnd(snaps),
            appliedDomains: e.domains,
            appliedAppBundleIds: e.apps,
            nextTriggerDescription: nil,
            pfApplied: blocker.isApplied(),
            locks: locks,
            appendTargetBlockSetId: appendTarget,
            engineDegraded: engineDegraded)
    }

    // when the user is fully free: the latest endsAt across active snapshots (stable, won't jump between polls)
    private func latestEnd(_ snaps: [LockSnapshot]) -> Date? {
        snaps.map { $0.endsAt }.max()
    }

    private func nextTriggerDescription(calendar: Calendar) -> String? {
        let config = loadConfig()
        guard let next = Scheduler.nextStart(config, after: Date(), calendar: calendar) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: next)
    }

    func loadConfig() -> ScheduleConfig { configStore.load() ?? ScheduleConfig(rules: []) }
    func loadSnapshots() -> [LockSnapshot] { snapshotStore.load() }

    func resolveDomains(forBlockSetId id: String) -> [String] {
        loadConfig().blockSets.first(where: { $0.id == id })?.domains ?? []
    }

    private func pushAppUnion(_ snaps: [LockSnapshot]) {
        let e = EffectiveBlock.resolve(snaps)
        appBlocker.update(active: !e.apps.isEmpty, bundleIds: e.apps)
    }

    func pushClearedSnapshot() {
        appBlocker.update(active: false, bundleIds: [])
    }
}
