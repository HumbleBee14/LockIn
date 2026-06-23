import Foundation

public final class BlockController {
    private let store: LockStateStore
    private let clockGuard: ClockGuard
    private let configStore: ConfigStore
    private let agentBridge: AgentBridging
    private let blocker = WebsiteBlocker()

    init(store: LockStateStore, clockGuard: ClockGuard, configStore: ConfigStore = .shared,
         agentBridge: AgentBridging = AgentBridge()) {
        self.store = store
        self.clockGuard = clockGuard
        self.configStore = configStore
        self.agentBridge = agentBridge
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

    func startQuickLock(blockSetIds: [String], durationSeconds: Double) -> Bool {
        // a quick lock may start ONLY when nothing is active (the UI enforces this too)
        if let s = store.load(), s.active { return false }
        let config = persistedConfig()
        let sets = blockSetIds.compactMap { id in config.blockSets.first { $0.id == id } }
        guard let first = sets.first else { return false }
        // all selected sets must share one mode; mixing allow/block is rejected
        guard sets.allSatisfy({ $0.mode == first.mode }) else { return false }

        var domains: [String] = []
        var apps: [String] = []
        var seenD = Set<String>(), seenA = Set<String>()
        for set in sets {
            for d in set.domains where seenD.insert(d).inserted { domains.append(d) }
            for a in set.appBundleIds where seenA.insert(a).inserted { apps.append(a) }
        }
        guard !domains.isEmpty else { return false }
        if domains.count > BlockLimits.maxActiveDomains {
            domains = Array(domains.prefix(BlockLimits.maxActiveDomains))
        }

        let title = sets.count == 1 ? first.name : "\(first.name) +\(sets.count - 1)"
        let now = Date()
        let state = LockState(active: true, mode: .adHoc, windowEnd: nil, duration: durationSeconds,
            anchorWallTime: now, trustedNowAtLastHeartbeat: now, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: SystemBootSession().uuid,
            appliedDomains: domains, appliedAppBundleIds: apps,
            appliedSettings: config.settings,
            isAllowlist: first.mode == .allowlist, blockSetId: first.id, blockSetTitle: title, scheduleRuleId: nil)
        activate(state)
        return true
    }

    // append-only, blocklist-only edit to the active block (the one change allowed mid-lock)
    func appendDomainsToActiveBlock(_ domains: [String]) -> Bool {
        guard var s = store.load(), s.active, !s.isAllowlist else { return false }
        var merged = s.appliedDomains
        for d in domains where !merged.contains(d) { merged.append(d) }
        guard merged.count != s.appliedDomains.count else { return true }
        s.appliedDomains = merged
        try? store.save(s)
        blocker.apply(domains: merged, allowlist: false)
        return true
    }

    private func persistedConfig() -> ScheduleConfig {
        configStore.load() ?? ScheduleConfig(rules: [])
    }

    // single-lock activation: write state, apply the block, push the app snapshot
    private func activate(_ state: LockState) {
        try? store.save(state)
        blocker.apply(domains: state.appliedDomains, allowlist: state.isAllowlist)
        pushAppSnapshot(for: state)
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
            nextTriggerDescription: nil)
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
    func reassert(_ s: LockState) { blocker.reassertIfTampered(domains: s.appliedDomains, allowlist: s.isAllowlist) }
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
        guard let set = loadConfig().blockSets.first(where: { $0.id == rule.blockSetId }) else { return }
        let now = Date()
        // a schedule trigger preempts a quick lock or a different active schedule (latest-active-wins)
        let state = LockState(active: true, mode: .scheduled, windowEnd: windowEnd, duration: nil,
            anchorWallTime: now, trustedNowAtLastHeartbeat: now, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: SystemBootSession().uuid,
            appliedDomains: set.domains, appliedAppBundleIds: rule.appBundleIds,
            appliedSettings: loadConfig().settings,
            isAllowlist: set.mode == .allowlist, blockSetTitle: set.name, scheduleRuleId: rule.id)
        activate(state)
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
