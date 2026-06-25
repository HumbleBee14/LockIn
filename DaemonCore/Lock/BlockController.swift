import Foundation

public final class BlockController {
    private let store: LockStateStore
    private let clockGuard: ClockGuard
    private let configStore: ConfigStore
    private let agentBridge: AgentBridging
    private let blocker: WebsiteBlocker

    init(store: LockStateStore, clockGuard: ClockGuard, configStore: ConfigStore = .shared,
         agentBridge: AgentBridging = AgentBridge(), blocker: WebsiteBlocker = WebsiteBlocker()) {
        self.store = store
        self.clockGuard = clockGuard
        self.configStore = configStore
        self.agentBridge = agentBridge
        self.blocker = blocker
    }

    public static func makeSystemController() -> BlockController {
        let store = LockStateStore(
            path: URL(fileURLWithPath: "/Library/Application Support/LockIn/active.plist"))
        let guard_ = ClockGuard(wall: SystemWallClock(), monotonic: SystemMonotonicClock(),
                                boot: SystemBootSession(), trusted: TrustedTime.system())
        return BlockController(store: store, clockGuard: guard_)
    }

    func registerSchedule(_ config: ScheduleConfig) -> Bool {
        // invariant: never mutate an active block's snapshot; edits affect future blocks only
        try? configStore.save(config)
        return true
    }

    // shared merge/dedup/cap used by both quick lock and scheduled lock so their logic can't diverge
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
            for d in set.domains where seenD.insert(d).inserted { domains.append(d) }
            for a in set.appBundleIds where seenA.insert(a).inserted { apps.append(a) }
        }
        guard !domains.isEmpty else { return nil }
        if domains.count > BlockLimits.maxActiveDomains {
            domains = Array(domains.prefix(BlockLimits.maxActiveDomains))
        }
        let title = sets.count == 1 ? first.name : "\(first.name) +\(sets.count - 1)"
        return ResolvedBlock(domains: domains, apps: apps,
                             isAllowlist: first.mode == .allowlist, primaryId: first.id, title: title)
    }

    func startQuickLock(blockSetIds: [String], durationSeconds: Double) -> Bool {
        startQuickLockReason(blockSetIds: blockSetIds, durationSeconds: durationSeconds) == nil
    }

    // nil on success; otherwise a short reason for the failure so the app can show it
    func startQuickLockReason(blockSetIds: [String], durationSeconds: Double) -> String? {
        if let s = store.load(), s.active { return "A lock is already active." }
        let config = persistedConfig()
        guard let r = resolveSets(blockSetIds, in: config) else {
            return "No valid sites to block (the selected sets are empty or mix allow/block modes)."
        }
        let now = Date()
        let state = LockState(active: true, mode: .adHoc, windowEnd: nil, duration: durationSeconds,
            anchorWallTime: now, trustedNowAtLastHeartbeat: now, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: SystemBootSession().uuid,
            appliedDomains: r.domains, appliedAppBundleIds: r.apps,
            appliedSettings: config.settings,
            isAllowlist: r.isAllowlist, blockSetId: r.primaryId, blockSetTitle: r.title, scheduleRuleId: nil)
        return activate(state) ? nil : "The block couldn’t be written to the system hosts file."
    }

    // append-only, blocklist-only edit to the active block (the one change allowed mid-lock)
    func appendDomainsToActiveBlock(_ domains: [String]) -> Bool {
        guard var s = store.load(), s.active, !s.isAllowlist else { return false }
        let existing = Set(s.appliedDomains)
        let fresh = domains.filter { !existing.contains($0) }
        guard !fresh.isEmpty else { return true }
        guard s.appliedDomains.count + fresh.count <= BlockLimits.maxActiveDomains else { return false }
        // invariant: only record the domains in the snapshot once hosts actually carries them
        guard blocker.appendToActiveBlock(newDomains: fresh,
                                          expandSubdomains: s.appliedSettings.expandSubdomains) else { return false }
        s.appliedDomains.append(contentsOf: fresh)
        try? store.save(s)
        return true
    }

    private func persistedConfig() -> ScheduleConfig {
        configStore.load() ?? ScheduleConfig(rules: [])
    }

    // recovery: rewrite /etc/hosts to the macOS default — refused while a lock is active (would be a bypass)
    func resetHostsToDefault() -> Bool {
        if let s = store.load(), s.active { return false }
        return blocker.resetToSystemDefault()
    }

    // root-side cleanup for uninstall: reset hosts, clear snapshot + root config. Refused while locked.
    func prepareUninstall() -> Bool {
        if let s = store.load(), s.active { return false }
        let ok = blocker.resetToSystemDefault()
        try? store.clear()
        try? configStore.save(ScheduleConfig(rules: []))
        return ok
    }

    // invariant: roll back fully if the block didn't apply, so no active state is left on failure
    private func activate(_ state: LockState) -> Bool {
        try? store.save(state)
        let applied = blocker.apply(domains: state.appliedDomains, allowlist: state.isAllowlist,
                                    expandSubdomains: state.appliedSettings.expandSubdomains)
        guard applied else {
            blocker.clear()
            try? store.clear()
            return false
        }
        pushAppSnapshot(for: state)
        return true
    }

    func currentStatus() -> LockState? {
        store.load()
    }

    public func statusDTO(calendar: Calendar = .current) -> DaemonStatus {
        guard let s = store.load(), s.active else {
            return DaemonStatus(active: false, source: nil, blockSetTitle: nil, isAllowlist: false,
                endsAt: nil, appliedDomains: [], nextTriggerDescription: nextTriggerDescription(calendar: calendar))
        }
        return DaemonStatus(
            active: true,
            source: s.mode == .adHoc ? "quick" : "scheduled",
            blockSetId: s.blockSetId,
            blockSetTitle: s.blockSetTitle,
            isAllowlist: s.isAllowlist,
            endsAt: endsAt(for: s),
            appliedDomains: s.appliedDomains,
            nextTriggerDescription: nil,
            pfApplied: blocker.isApplied())
    }

    private func endsAt(for s: LockState) -> Date? {
        switch s.mode {
        case .scheduled: return s.windowEnd
        case .adHoc:
            guard let d = s.duration else { return nil }
            let remaining = d - s.servedElapsedAtLastHeartbeat
            return Date().addingTimeInterval(max(0, remaining))
        }
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

    func loadState() -> LockState? { store.load() }
    func saveState(_ s: LockState) { try? store.save(s) }
    func clearState() { try? store.clear() }
    func loadConfig() -> ScheduleConfig { configStore.load() ?? ScheduleConfig(rules: []) }
    func guardHeartbeat(_ s: LockState) -> LockState { clockGuard.heartbeat(s) }
    func guardIsExpired(_ s: LockState) -> Bool { clockGuard.isExpired(s) }
    func clearBlocking() { blocker.clear() }
    func reassert(_ s: LockState) { blocker.reassertIfTampered(domains: s.appliedDomains, allowlist: s.isAllowlist, expandSubdomains: s.appliedSettings.expandSubdomains) }
    func currentTrustedWallNow() -> Date {
        if let s = store.load() { return clockGuard.trustedNow(s) }
        return Date()
    }
    func resolveDomains(forBlockSetId id: String) -> [String] {
        loadConfig().blockSets.first(where: { $0.id == id })?.domains ?? []
    }

    // suspicious + offline => unresolved, so the block is held rather than evaluated
    public func timeIsResolved() -> Bool {
        if clockGuard.hasTrustedTime() { return true }
        if let s = store.load() { return !s.clockSuspicious }
        return true
    }

    func startScheduled(rule: Rule, windowEnd: Date?) {
        // already enforcing THIS rule: nothing to do (don't reset its timer each tick)
        if let s = store.load(), s.active, s.scheduleRuleId == rule.id { return }
        let config = loadConfig()
        // don't fire if every set is deleted/empty or modes conflict — nothing valid to enforce
        guard let r = resolveSets(rule.blockSetIds, in: config) else { return }
        let now = Date()
        // a schedule trigger preempts a quick lock or a different active schedule (latest-active-wins)
        let state = LockState(active: true, mode: .scheduled, windowEnd: windowEnd, duration: nil,
            anchorWallTime: now, trustedNowAtLastHeartbeat: now, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: SystemBootSession().uuid,
            appliedDomains: r.domains, appliedAppBundleIds: r.apps,
            appliedSettings: config.settings,
            isAllowlist: r.isAllowlist, blockSetId: r.primaryId, blockSetTitle: r.title, scheduleRuleId: rule.id)
        _ = activate(state)
    }

    // app-blocking off => push an empty list so the agent kills nothing
    private func pushAppSnapshot(for state: LockState) {
        let bundleIds = state.appliedSettings.appBlockingEnabled ? state.appliedAppBundleIds : []
        agentBridge.push(BlockedAppSnapshot(active: true, bundleIds: bundleIds))
    }

    func pushClearedSnapshot() {
        agentBridge.push(BlockedAppSnapshot(active: false, bundleIds: []))
    }
}
