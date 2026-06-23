import XCTest
@testable import LockInDaemonCore

final class RegisterScheduleInvariantTests: XCTestCase {
    func testRegisterScheduleDoesNotWeakenActiveBlock() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-inv.plist")
        let cfgURL = FileManager.default.temporaryDirectory.appendingPathComponent("config-inv.plist")
        let store = LockStateStore(path: url)
        let active = LockState(active: true, mode: .scheduled,
            windowEnd: Date(timeIntervalSinceNow: 3600), duration: nil,
            anchorWallTime: Date(), trustedNowAtLastHeartbeat: Date(),
            servedElapsedAtLastHeartbeat: 0, clockSuspicious: false, bootSessionUUID: "B",
            appliedDomains: ["youtube.com"], appliedAppBundleIds: [])
        try store.save(active)
        let controller = BlockController(store: store, clockGuard: makeTestGuard(boot: "B"),
                                         configStore: ConfigStore(path: cfgURL))
        _ = controller.registerSchedule(ScheduleConfig(rules: []))
        let after = store.load()
        XCTAssertEqual(after?.appliedDomains, ["youtube.com"], "active snapshot must be immutable")
        XCTAssertEqual(after?.windowEnd, active.windowEnd, "cannot move window earlier")
        XCTAssertEqual(after?.active, true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfgURL)
    }

    private func makeTestGuard(boot: String) -> ClockGuard {
        ClockGuard(wall: FakeWallClock(Date()), monotonic: FakeMonotonicClock(0),
                   boot: FakeBootSession(boot), trusted: FakeTrustedTimeSource(nil))
    }
}
