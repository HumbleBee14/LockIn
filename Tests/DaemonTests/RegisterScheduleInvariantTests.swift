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
        try store.save([LockSnapshot(id: "r", mode: .scheduled, windowEnd: end, duration: nil,
            isAllowlist: false, appliedDomains: ["youtube.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B", anchorWallTime: Date(),
            trustedNowAtLastHeartbeat: Date(), servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, cumulativeDriftSeconds: 0, bootSessionUUID: "B")])
        let controller = BlockController(snapshotStore: store, configStore: ConfigStore(path: cfgURL),
                                         agentBridge: SpyAgentBridge(), blocker: WebsiteBlocker(forceVerified: true))
        _ = controller.registerSchedule(ScheduleConfig(rules: []))
        let after = store.load()
        XCTAssertEqual(after.first?.appliedDomains, ["youtube.com"], "active snapshot must be immutable")
        XCTAssertEqual(after.first?.windowEnd, end, "cannot move window earlier")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfgURL)
    }
}
