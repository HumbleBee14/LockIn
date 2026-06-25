import XCTest
@testable import LockInDaemonCore

@MainActor
final class WatchdogTests: XCTestCase {
    func testWebsiteBlockStateIndependentOfAgent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-wd.plist")
        try? FileManager.default.removeItem(at: url)
        let store = LockSnapshotStore(path: url)
        try store.save([LockSnapshot(id: "r", mode: .scheduled, windowEnd: Date(timeIntervalSinceNow: 3600),
            duration: nil, isAllowlist: false, appliedDomains: ["x.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B", anchorWallTime: Date(),
            trustedNowAtLastHeartbeat: Date(), servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, cumulativeDriftSeconds: 0, bootSessionUUID: "B")])
        let controller = BlockController(snapshotStore: store,
            configStore: ConfigStore(path: FileManager.default.temporaryDirectory
                .appendingPathComponent("config-wd.plist")),
            appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true))
        controller.applyDecisionIfNeeded(timeResolved: true)
        XCTAssertFalse(store.load().isEmpty,
                      "website lock state is owned by the daemon and unaffected by the agent")
        try? FileManager.default.removeItem(at: url)
    }
}
