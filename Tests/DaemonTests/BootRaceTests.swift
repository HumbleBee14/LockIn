import XCTest
@testable import LockInDaemonCore

final class BootRaceTests: XCTestCase {
    func testBlockHeldDuringPostBootBeforeTimeResolved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-boot.plist")
        let store = LockStateStore(path: url)
        try store.save(LockState(active: true, mode: .scheduled,
            windowEnd: Date(timeIntervalSinceNow: 3600), duration: nil, anchorWallTime: Date(),
            trustedNowAtLastHeartbeat: Date(), servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, bootSessionUUID: "B", appliedDomains: ["x.com"], appliedAppBundleIds: []))
        let guard_ = ClockGuard(wall: FakeWallClock(Date()), monotonic: FakeMonotonicClock(0),
                                boot: FakeBootSession("B"), trusted: FakeTrustedTimeSource(nil))
        let controller = BlockController(store: store, clockGuard: guard_,
                                         configStore: ConfigStore(path: tmpConfig()))
        controller.applyDecisionIfNeeded(timeResolved: false)
        XCTAssertTrue(store.load()?.active == true, "must hold the block until time resolves")
        try? FileManager.default.removeItem(at: url)
    }

    private func tmpConfig() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("config-boot.plist")
    }
}
