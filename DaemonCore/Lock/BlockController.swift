import Foundation

public final class BlockController {
    private let store: LockStateStore
    private let clockGuard: ClockGuard
    private let configStore: ConfigStore
    private let blocker = WebsiteBlocker()

    init(store: LockStateStore, clockGuard: ClockGuard, configStore: ConfigStore = .shared) {
        self.store = store
        self.clockGuard = clockGuard
        self.configStore = configStore
    }

    public static func makeSystemController() -> BlockController {
        let store = LockStateStore(
            path: URL(fileURLWithPath: "/Library/Application Support/LockIn/active.plist"))
        let guard_ = ClockGuard(wall: SystemWallClock(), monotonic: SystemMonotonicClock(),
                                boot: SystemBootSession(), trusted: PinnedTrustedTimeSource(hosts: []))
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
        return true
    }

    func currentStatus() -> LockState? {
        store.load()
    }
}
