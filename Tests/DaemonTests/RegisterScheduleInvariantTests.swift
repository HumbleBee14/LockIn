import XCTest
@testable import LockInDaemonCore

@MainActor
final class RegisterScheduleInvariantTests: XCTestCase {
    func testRegisterScheduleDoesNotWeakenActiveSnapshot() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-inv.plist")
        let cfgURL = FileManager.default.temporaryDirectory.appendingPathComponent("config-inv.plist")
        try? FileManager.default.removeItem(at: url)
        let store = LockSnapshotStore(path: url)
        let end = Date(timeIntervalSinceNow: 3600)
        try store.save([LockSnapshot(id: "r", mode: .scheduled, endsAt: end,
            isAllowlist: false, appliedDomains: ["youtube.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")])
        let controller = BlockController(snapshotStore: store, configStore: ConfigStore(path: cfgURL),
                                         appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true))
        _ = controller.registerSchedule(ScheduleConfig(rules: []))
        let after = store.load()
        XCTAssertEqual(after.first?.appliedDomains, ["youtube.com"], "active snapshot must be immutable")
        XCTAssertEqual(after.first?.endsAt, end, "cannot move the end earlier")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfgURL)
    }
}
