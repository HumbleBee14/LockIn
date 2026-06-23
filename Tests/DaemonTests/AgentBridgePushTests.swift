import XCTest
@testable import LockInDaemonCore

final class AgentBridgePushTests: XCTestCase {
    func testStartBlockPushesActiveSnapshot() {
        let bridge = SpyAgentBridge()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push.plist")
        try? FileManager.default.removeItem(at: url)
        let guard_ = ClockGuard(wall: FakeWallClock(Date()), monotonic: FakeMonotonicClock(0),
                                boot: FakeBootSession("B"), trusted: FakeTrustedTimeSource(nil))
        let controller = BlockController(store: LockStateStore(path: url), clockGuard: guard_,
                                         configStore: ConfigStore(path: cfg), agentBridge: bridge)
        _ = controller.startAdHoc(blockSetId: "x", durationSeconds: 60,
                                  domains: [], appBundleIds: ["com.tinyspeck.slackmacgap"])
        XCTAssertEqual(bridge.lastPushed?.active, true)
        XCTAssertEqual(bridge.lastPushed?.bundleIds, ["com.tinyspeck.slackmacgap"])
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }
}

final class SpyAgentBridge: AgentBridging {
    var lastPushed: BlockedAppSnapshot?
    func push(_ snapshot: BlockedAppSnapshot) { lastPushed = snapshot }
}
