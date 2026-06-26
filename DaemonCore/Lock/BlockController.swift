import Foundation

// what the engine should currently be enforcing — compared tick-to-tick so we re-apply only on real change
enum EngineDesire: Equatable {
    case clear
    case block(domains: Set<String>, allowlist: Bool, expand: Bool)
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
        // the UI only offers quick lock from the fully-unlocked state, so an existing set means already locked
        if !snapshotStore.load().isEmpty { return "A lock is already active." }
        let config = persistedConfig()
        if domainCount(blockSetIds, in: config) > BlockLimits.maxActiveDomains {
            return "This block set is too large (over \(BlockLimits.maxActiveDomains) sites). Split it into smaller sets."
        }
        guard let r = resolveSets(blockSetIds, in: config) else {
            return "No valid sites to block (the selected sets are empty or mix allow/block modes)."
        }
        let snap = freshSnapshot(id: "quick", mode: .adHoc, endsAt: now().addingTimeInterval(durationSeconds),
                                 r: r, settings: config.settings)
        // synchronous here: the user is waiting on this XPC reply for success/failure (not the timer thread)
        let applied = blocker.apply(domains: r.domains, allowlist: r.isAllowlist,
                                    expandSubdomains: config.settings.expandSubdomains)
        guard applied else { blocker.clearAsync(); return "Block not applied at the system level. Lock aborted." }
        desiredEngine = .block(domains: Set(r.domains), allowlist: r.isAllowlist, expand: config.settings.expandSubdomains)
        try? snapshotStore.save([snap])
        appliedSnapshotIds = [snap.id]
        pushAppUnion([snap])
        return nil
    }

    // append-only, blocklist-only edit to the matching active snapshot (the one change allowed mid-lock)
    func appendDomainsToActiveBlock(_ domains: [String]) -> Bool {
        var snaps = snapshotStore.load()
        guard let i = snaps.firstIndex(where: { !$0.isAllowlist }) else { return false }
        let existing = Set(snaps[i].appliedDomains)
        // invariant: same control-char/marker rejection as resolveSets — never write a raw XPC string to /etc/hosts
        let fresh = domains.filter { Self.isSafeDomain($0) && !existing.contains($0) }
        guard !fresh.isEmpty else { return true }
        guard snaps[i].appliedDomains.count + fresh.count <= BlockLimits.maxActiveDomains else { return false }
        // invariant: only record the domains in the snapshot once hosts actually carries them
        guard blocker.appendToActiveBlock(newDomains: fresh,
                                          expandSubdomains: snaps[i].appliedSettings.expandSubdomains) else { return false }
        snaps[i].appliedDomains.append(contentsOf: fresh)
        try? snapshotStore.save(snaps)
        // keep desired state in step with the larger set so the next tick doesn't trigger a full rebuild
        let e = EffectiveBlock.resolve(snaps)
        desiredEngine = .block(domains: Set(e.domains), allowlist: e.isAllowlist,
                               expand: snaps[i].appliedSettings.expandSubdomains)
        return true
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
        let want = EngineDesire.block(domains: Set(e.domains), allowlist: e.isAllowlist,
                                      expand: first.appliedSettings.expandSubdomains)
        // re-apply only when the desired set actually changed, OR the live block drifted (tamper self-heal)
        let drifted = !blocker.blockIntact(domains: e.domains, allowlist: e.isAllowlist,
                                           expandSubdomains: first.appliedSettings.expandSubdomains)
        if want != desiredEngine || drifted {
            desiredEngine = want
            blocker.applyAsync(domains: e.domains, allowlist: e.isAllowlist,
                               expandSubdomains: first.appliedSettings.expandSubdomains)
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

    // recovery: always overwrites /etc/hosts with the macOS default. unconditional by design — it's the escape
    // hatch when state is wrong. runs off-main on the engine queue so an in-flight 70K apply can't wedge it.
    func resetHostsToDefault(completion: @escaping @Sendable (Bool) -> Void) {
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
            pfApplied: blocker.isApplied())
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
