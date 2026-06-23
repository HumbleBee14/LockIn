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
        // anti-bypass invariant: never mutate an active block's snapshot; edits affect FUTURE only.
        try? configStore.save(config)
        return true
    }

    func startAdHocBlock(blockSetId: String, durationSeconds: Double) -> Bool {
        guard let set = persistedConfig().blockSets.first(where: { $0.id == blockSetId }) else {
            return false
        }
        return startAdHoc(blockSetId: blockSetId, durationSeconds: durationSeconds,
                          domains: set.domains, appBundleIds: set.appBundleIds)
    }

    private func persistedConfig() -> ScheduleConfig {
        configStore.load() ?? ScheduleConfig(rules: [])
    }

    @discardableResult
    func startAdHoc(blockSetId: String, durationSeconds: Double, domains: [String],
                    appBundleIds: [String] = []) -> Bool {
        if let s = store.load(), s.active { return false }
        let now = Date()
        let settings = persistedConfig().settings
        let state = LockState(active: true, mode: .adHoc, windowEnd: nil, duration: durationSeconds,
            anchorWallTime: now, trustedNowAtLastHeartbeat: now, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: SystemBootSession().uuid,
            appliedDomains: domains, appliedAppBundleIds: appBundleIds, appliedSettings: settings)
        try? store.save(state)
        blocker.apply(domains: domains)
        pushAppSnapshot(for: state)
        return true
    }

    func currentStatus() -> LockState? {
        store.load()
    }

    public func statusDTO(calendar: Calendar = .current) -> DaemonStatus {
        let state = store.load()
        let next = nextTriggerDescription(calendar: calendar)
        return DaemonStatus(
            active: state?.active ?? false,
            mode: state?.mode.rawValue,
            windowEnd: state?.windowEnd,
            appliedDomains: state?.appliedDomains ?? [],
            nextTriggerDescription: next)
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
    func reassert(domains: [String]) { blocker.reassertIfTampered(domains: domains) }
    func currentTrustedWallNow() -> Date {
        if let s = store.load() { return clockGuard.trustedNow(s) }
        return Date()
    }
    func resolveDomains(forBlockSetId id: String) -> [String] {
        loadConfig().blockSets.first(where: { $0.id == id })?.domains ?? []
    }

    // bias to blocked: suspicious + offline => unresolved, so applyDecisionIfNeeded holds the block
    public func timeIsResolved() -> Bool {
        if clockGuard.hasTrustedTime() { return true }
        if let s = store.load() { return !s.clockSuspicious }
        return true
    }

    func startScheduled(rule: Rule, windowEnd: Date?, domains: [String], appBundleIds: [String]) {
        if let s = store.load(), s.active { return }
        let now = Date()
        let settings = loadConfig().settings
        let state = LockState(active: true, mode: .scheduled, windowEnd: windowEnd, duration: nil,
            anchorWallTime: now, trustedNowAtLastHeartbeat: now, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: SystemBootSession().uuid,
            appliedDomains: domains, appliedAppBundleIds: appBundleIds, appliedSettings: settings)
        try? store.save(state)
        blocker.apply(domains: domains)
        pushAppSnapshot(for: state)
    }

    // app-blocking off (snapshotted setting) => push empty so the agent kills nothing
    private func pushAppSnapshot(for state: LockState) {
        let bundleIds = state.appliedSettings.appBlockingEnabled ? state.appliedAppBundleIds : []
        agentBridge.push(BlockedAppSnapshot(active: true, bundleIds: bundleIds))
    }

    func pushClearedSnapshot() {
        agentBridge.push(BlockedAppSnapshot(active: false, bundleIds: []))
    }
}
