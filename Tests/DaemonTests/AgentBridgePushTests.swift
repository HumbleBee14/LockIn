import XCTest
@testable import LockInDaemonCore

final class AgentBridgePushTests: XCTestCase {
    private func makeController(settings: SettingsConfig, bridge: AgentBridging,
                               url: URL, cfg: URL) throws -> BlockController {
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        let set = BlockSet(id: "x", name: "Test", domains: ["youtube.com"],
                           appBundleIds: ["com.tinyspeck.slackmacgap"])
        try cfgStore.save(ScheduleConfig(rules: [], blockSets: [set], settings: settings))
        let guard_ = ClockGuard(wall: FakeWallClock(Date()), monotonic: FakeMonotonicClock(0),
                                boot: FakeBootSession("B"), trusted: FakeTrustedTimeSource(nil))
        let blocker = WebsiteBlocker(verify: { _, _ in true })
        return BlockController(store: LockStateStore(path: url), clockGuard: guard_,
                               configStore: cfgStore, agentBridge: bridge, blocker: blocker)
    }

    func testStartBlockPushesActiveSnapshot() throws {
        let bridge = SpyAgentBridge()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push.plist")
        let controller = try makeController(settings: SettingsConfig(), bridge: bridge, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertEqual(bridge.lastPushed?.active, true)
        XCTAssertEqual(bridge.lastPushed?.bundleIds, ["com.tinyspeck.slackmacgap"])
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }

    func testAppBlockingDisabledPushesEmptyBundleList() throws {
        let bridge = SpyAgentBridge()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push2.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push2.plist")
        var settings = SettingsConfig()
        settings.appBlockingEnabled = false
        let controller = try makeController(settings: settings, bridge: bridge, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertEqual(bridge.lastPushed?.active, true)
        XCTAssertEqual(bridge.lastPushed?.bundleIds, [],
            "app-blocking OFF must push an empty list so the agent kills nothing")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }

    func testQuickLockRefusedWhenAlreadyActive() throws {
        let bridge = SpyAgentBridge()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push3.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push3.plist")
        let controller = try makeController(settings: SettingsConfig(), bridge: bridge, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertFalse(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60),
            "a second quick lock must be refused while one is active")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }
}

final class SpyAgentBridge: AgentBridging {
    var lastPushed: BlockedAppSnapshot?
    func push(_ snapshot: BlockedAppSnapshot) { lastPushed = snapshot }
}
