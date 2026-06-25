import XCTest
@testable import LockInDaemonCore

@MainActor
final class AppBlockerUpdateTests: XCTestCase {
    private func makeController(settings: SettingsConfig, spy: SpyAppBlocker,
                               url: URL, cfg: URL) throws -> BlockController {
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        let set = BlockSet(id: "x", name: "Test", domains: ["youtube.com"],
                           appBundleIds: ["com.tinyspeck.slackmacgap"])
        try cfgStore.save(ScheduleConfig(rules: [], blockSets: [set], settings: settings))
        let blocker = WebsiteBlocker(forceVerified: true)
        return BlockController(snapshotStore: LockSnapshotStore(path: url),
                               configStore: cfgStore, appBlocker: spy, blocker: blocker)
    }

    func testStartBlockUpdatesAppBlockerActive() throws {
        let spy = SpyAppBlocker()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push.plist")
        let controller = try makeController(settings: SettingsConfig(), spy: spy, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertEqual(spy.lastActive, true)
        XCTAssertEqual(spy.lastBundleIds, ["com.tinyspeck.slackmacgap"])
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }

    func testAppBlockingDisabledUpdatesEmptyBundleList() throws {
        let spy = SpyAppBlocker()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push2.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push2.plist")
        var settings = SettingsConfig()
        settings.appBlockingEnabled = false
        let controller = try makeController(settings: settings, spy: spy, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertEqual(spy.lastActive, false)
        XCTAssertEqual(spy.lastBundleIds, [],
            "app-blocking OFF must update an empty list so the daemon kills nothing")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }

    func testQuickLockRefusedWhenAlreadyActive() throws {
        let spy = SpyAppBlocker()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push3.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push3.plist")
        let controller = try makeController(settings: SettingsConfig(), spy: spy, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertFalse(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60),
            "a second quick lock must be refused while one is active")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }
}

final class SpyAppBlocker: AppBlocking {
    var lastActive: Bool?
    var lastBundleIds: [String]?
    func update(active: Bool, bundleIds: [String]) { lastActive = active; lastBundleIds = bundleIds }
    func isMonitoring() -> Bool { lastActive == true && !(lastBundleIds?.isEmpty ?? true) }
    func sweepNow() {}
}
