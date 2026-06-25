import Foundation

// invariant: main-actor isolated so the timer loop and XPC handlers can't race on lock state
@MainActor
public final class BlockController {
    private let snapshotStore: LockSnapshotStore
    private let configStore: ConfigStore
    private let appBlocker: AppBlocking
    private let blocker: WebsiteBlocker
    private let makeGuard: () -> ClockGuard
    private var guards: [String: ClockGuard] = [:]

    init(snapshotStore: LockSnapshotStore, configStore: ConfigStore = .shared,
         appBlocker: AppBlocking = AppBlocker(), blocker: WebsiteBlocker = WebsiteBlocker(),
         makeGuard: @escaping () -> ClockGuard = {
             ClockGuard(wall: SystemWallClock(), monotonic: SystemMonotonicClock(),
                        boot: SystemBootSession(), trusted: TrustedTime.system())
         }) {
        self.snapshotStore = snapshotStore
        self.configStore = configStore
        self.appBlocker = appBlocker
        self.blocker = blocker
        self.makeGuard = makeGuard
    }

    public static func makeSystemController() -> BlockController {
        BlockController(snapshotStore: LockSnapshotStore(
            path: URL(fileURLWithPath: "/Library/Application Support/LockIn/active.plist")))
    }

    private func guardFor(_ id: String) -> ClockGuard {
        if let g = guards[id] { return g }
        let g = makeGuard()
        guards[id] = g
        return g
    }

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
        let snap = freshSnapshot(id: "quick", mode: .adHoc, windowEnd: nil, duration: durationSeconds,
                                 r: r, settings: config.settings)
        let applied = blocker.apply(domains: r.domains, allowlist: r.isAllowlist,
                                    expandSubdomains: config.settings.expandSubdomains)
        guard applied else { blocker.clear(); return "Block not applied at the system level. Lock aborted." }
        try? snapshotStore.save([snap])
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
        return true
    }

    // the reconcile tick: heartbeat all, drop expired, apply the effective union, then add newly-due rules
    func reconcile(calendar: Calendar = .current) {
        reconcile(calendar: calendar, servedExpiryOnly: false)
    }

    // invariant: servedExpiryOnly lifts only served-expired ad-hoc locks; never evaluates scheduled (wall-time) expiry or new rules
    func reconcile(calendar: Calendar, servedExpiryOnly: Bool) {
        var snaps = snapshotStore.load().map { guardFor($0.id).heartbeat($0) }
        let survivors = snaps.filter { snap in
            if servedExpiryOnly && snap.mode != .adHoc { return true }
            return !guardFor(snap.id).isExpired(snap)
        }
        for dropped in snaps where !survivors.contains(where: { $0.id == dropped.id }) {
            guards[dropped.id] = nil
        }
        snaps = survivors
        applyEffective(snaps)
        if !servedExpiryOnly { addNewlyDueRules(into: &snaps, calendar: calendar) }
        if snaps.isEmpty {
            try? snapshotStore.clear()
            blocker.clear()
            pushClearedSnapshot()
        } else {
            try? snapshotStore.save(snaps)
        }
    }

    private func applyEffective(_ snaps: [LockSnapshot]) {
        guard let first = snaps.first else { return }
        let e = EffectiveBlock.resolve(snaps)
        // reassert every tick so a tamper or a relaunched agent self-heals within one cycle
        _ = blocker.apply(domains: e.domains, allowlist: e.isAllowlist,
                          expandSubdomains: first.appliedSettings.expandSubdomains)
        pushAppUnion(snaps)
        // invariant: if the active block has apps but the killer stopped, re-arm it — bias toward staying blocked
        let on = first.appliedSettings.appBlockingEnabled
        if on && !e.apps.isEmpty && !appBlocker.isMonitoring() {
            appBlocker.update(active: true, bundleIds: e.apps)
        }
    }

    private func addNewlyDueRules(into snaps: inout [LockSnapshot], calendar: Calendar) {
        // invariant: config is read ONLY to detect a NEW rule starting; never to mutate a live snapshot
        let config = loadConfig()
        let now = currentTrustedWallNow(snaps)
        for rule in config.rules {
            guard !snaps.contains(where: { $0.id == rule.id }) else { continue }
            guard let end = Scheduler.activeWindowEndPublic(rule, at: now, calendar: calendar) else { continue }
            guard let r = resolveSets(rule.blockSetIds, in: config) else { continue }
            guard r.domains.count <= BlockLimits.maxActiveDomains else { continue }
            let snap = freshSnapshot(id: rule.id, mode: .scheduled, windowEnd: end, duration: nil,
                                     r: r, settings: config.settings)
            _ = blocker.apply(domains: EffectiveBlock.resolve(snaps + [snap]).domains,
                              allowlist: EffectiveBlock.resolve(snaps + [snap]).isAllowlist,
                              expandSubdomains: config.settings.expandSubdomains)
            snaps.append(snap)
        }
    }

    private func freshSnapshot(id: String, mode: BlockMode, windowEnd: Date?, duration: Double?,
                               r: ResolvedBlock, settings: SettingsConfig) -> LockSnapshot {
        let now = Date()
        return LockSnapshot(id: id, mode: mode, windowEnd: windowEnd, duration: duration,
            isAllowlist: r.isAllowlist, appliedDomains: r.domains, appliedAppBundleIds: r.apps,
            appliedSettings: settings, blockSetId: r.primaryId, blockSetTitle: r.title,
            anchorWallTime: now, trustedNowAtLastHeartbeat: now, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, cumulativeDriftSeconds: 0, bootSessionUUID: SystemBootSession().uuid)
    }

    private func persistedConfig() -> ScheduleConfig {
        configStore.load() ?? ScheduleConfig(rules: [])
    }

    // recovery: rewrite /etc/hosts to the macOS default — refused while a lock is active (would be a bypass)
    func resetHostsToDefault() -> Bool {
        if isLockHeld() { return false }
        return blocker.resetToSystemDefault()
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
            return DaemonStatus(active: false, source: nil, blockSetTitle: nil, isAllowlist: false,
                endsAt: nil, appliedDomains: [], nextTriggerDescription: nextTriggerDescription(calendar: calendar))
        }
        let e = EffectiveBlock.resolve(snaps)
        let anyScheduled = snaps.contains { $0.mode == .scheduled }
        let title = snaps.count == 1 ? snaps[0].blockSetTitle : "\(snaps[0].blockSetTitle) +\(snaps.count - 1)"
        let appsOn = snaps.first?.appliedSettings.appBlockingEnabled ?? false
        return DaemonStatus(
            active: true,
            source: anyScheduled ? "scheduled" : "quick",
            blockSetId: snaps[0].blockSetId,
            blockSetTitle: title,
            isAllowlist: e.isAllowlist,
            endsAt: latestEnd(snaps),
            appliedDomains: e.domains,
            appliedAppBundleIds: appsOn ? e.apps : [],
            nextTriggerDescription: nil,
            pfApplied: blocker.isApplied())
    }

    // the countdown shows when the user is FULLY free: the latest end across all active snapshots.
    // a quick lock's end is a STABLE absolute instant (anchor + duration) so the UI countdown can't
    // jump — recomputing "now + remaining" each poll would re-anchor it on every refresh.
    private func latestEnd(_ snaps: [LockSnapshot]) -> Date? {
        var latest: Date?
        for s in snaps {
            let end: Date?
            switch s.mode {
            case .scheduled: end = s.windowEnd
            case .adHoc:
                guard let d = s.duration else { end = nil; break }
                end = s.anchorWallTime.addingTimeInterval(d)
            }
            if let end, latest == nil || end > latest! { latest = end }
        }
        return latest
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

    // max trusted-now across active snapshots, so a new rule is evaluated against held (not raw) time
    private func currentTrustedWallNow(_ snaps: [LockSnapshot]) -> Date {
        snaps.map { $0.trustedNowAtLastHeartbeat }.max() ?? Date()
    }

    func resolveDomains(forBlockSetId id: String) -> [String] {
        loadConfig().blockSets.first(where: { $0.id == id })?.domains ?? []
    }

    // suspicious + offline on any active snapshot => unresolved, so the block is held rather than evaluated
    public func timeIsResolved() -> Bool {
        let snaps = snapshotStore.load()
        guard !snaps.isEmpty else { return true }
        if guardFor(snaps[0].id).hasTrustedTime() { return true }
        return !snaps.contains { $0.clockSuspicious }
    }

    private func pushAppUnion(_ snaps: [LockSnapshot]) {
        let e = EffectiveBlock.resolve(snaps)
        let on = snaps.first?.appliedSettings.appBlockingEnabled ?? false
        appBlocker.update(active: on, bundleIds: on ? e.apps : [])
    }

    func pushClearedSnapshot() {
        appBlocker.update(active: false, bundleIds: [])
    }
}
