import XCTest
@testable import LockInDaemonCore

final class WatchdogTests: XCTestCase {
    func testWebsiteBlockStateIndependentOfAgent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-wd.plist")
        let store = LockStateStore(path: url)
        try store.save(LockState(active: true, mode: .scheduled,
            windowEnd: Date(timeIntervalSinceNow: 3600), duration: nil, anchorWallTime: Date(),
            trustedNowAtLastHeartbeat: Date(), servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: "B", appliedDomains: ["x.com"], appliedAppBundleIds: []))
        let guard_ = ClockGuard(wall: FakeWallClock(Date()), monotonic: FakeMonotonicClock(0),
                                boot: FakeBootSession("B"), trusted: FakeTrustedTimeSource(nil))
        let controller = BlockController(store: store, clockGuard: guard_,
            configStore: ConfigStore(path: FileManager.default.temporaryDirectory
                .appendingPathComponent("config-wd.plist")))
        controller.applyDecisionIfNeeded(timeResolved: true)
        XCTAssertTrue(store.load()?.active == true,
                      "website lock state is owned by the daemon and unaffected by the agent")
        try? FileManager.default.removeItem(at: url)
    }
}
