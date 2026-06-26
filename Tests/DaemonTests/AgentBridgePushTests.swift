import XCTest
@testable import LockInDaemonCore

@MainActor
final class AppBlockerUpdateTests: XCTestCase {
    private func makeController(apps: [String], spy: SpyAppBlocker,
                               url: URL, cfg: URL) throws -> BlockController {
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        let set = BlockSet(id: "x", name: "Test", domains: ["youtube.com"], appBundleIds: apps)
        try cfgStore.save(ScheduleConfig(rules: [], blockSets: [set]))
        let blocker = WebsiteBlocker(forceVerified: true)
        return BlockController(snapshotStore: LockSnapshotStore(path: url),
                               configStore: cfgStore, appBlocker: spy, blocker: blocker)
    }

    func testStartBlockUpdatesAppBlockerActive() throws {
        let spy = SpyAppBlocker()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push.plist")
        let controller = try makeController(apps: ["com.tinyspeck.slackmacgap"], spy: spy, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertEqual(spy.lastActive, true)
        XCTAssertEqual(spy.lastBundleIds, ["com.tinyspeck.slackmacgap"])
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }

    // app blocking follows the blockset: no apps in the set => app blocker stays inactive
    func testNoAppsInSetLeavesAppBlockerInactive() throws {
        let spy = SpyAppBlocker()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push2.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push2.plist")
        let controller = try makeController(apps: [], spy: spy, url: url, cfg: cfg)
        XCTAssertTrue(controller.startQuickLock(blockSetIds: ["x"], durationSeconds: 60))
        XCTAssertEqual(spy.lastActive, false)
        XCTAssertEqual(spy.lastBundleIds, [])
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
    }

    func testQuickLockRefusedWhenAlreadyActive() throws {
        let spy = SpyAppBlocker()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-push3.plist")
        let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("config-push3.plist")
        let controller = try makeController(apps: ["com.tinyspeck.slackmacgap"], spy: spy, url: url, cfg: cfg)
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
