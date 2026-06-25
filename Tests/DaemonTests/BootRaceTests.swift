import XCTest
@testable import LockInDaemonCore

@MainActor
final class BootRaceTests: XCTestCase {
    func testBlockHeldDuringPostBootBeforeTimeResolved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-boot.plist")
        let store = LockSnapshotStore(path: url)
        try store.save([LockSnapshot(id: "r", mode: .scheduled, windowEnd: Date(timeIntervalSinceNow: 3600),
            duration: nil, isAllowlist: false, appliedDomains: ["x.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B", anchorWallTime: Date(),
            trustedNowAtLastHeartbeat: Date(), servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, cumulativeDriftSeconds: 0, bootSessionUUID: "B")])
        let controller = BlockController(snapshotStore: store, configStore: ConfigStore(path: tmpConfig()),
                                         appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true))
        controller.applyDecisionIfNeeded(timeResolved: false)
        XCTAssertFalse(store.load().isEmpty, "must hold the block until time resolves")
        try? FileManager.default.removeItem(at: url)
    }

    private func tmpConfig() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("config-boot.plist")
    }
}
