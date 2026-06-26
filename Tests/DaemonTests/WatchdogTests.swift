import XCTest
@testable import LockInDaemonCore

@MainActor
final class WatchdogTests: XCTestCase {
    func testWebsiteBlockStateIndependentOfAgent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-wd.plist")
        try? FileManager.default.removeItem(at: url)
        let store = LockSnapshotStore(path: url)
        try store.save([LockSnapshot(id: "r", mode: .scheduled, endsAt: Date(timeIntervalSinceNow: 3600),
            isAllowlist: false, appliedDomains: ["x.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")])
        let controller = BlockController(snapshotStore: store,
            configStore: ConfigStore(path: FileManager.default.temporaryDirectory
                .appendingPathComponent("config-wd.plist")),
            appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true))
        controller.applyDecisionIfNeeded()
        XCTAssertFalse(store.load().isEmpty,
                      "website lock state is owned by the daemon and unaffected by the agent")
        try? FileManager.default.removeItem(at: url)
    }
}
