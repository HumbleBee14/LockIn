import XCTest
@testable import LockInDaemonCore

@MainActor
final class BootRaceTests: XCTestCase {
    func testBlockHeldAfterRestartUntilEnd() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-boot.plist")
        let store = LockSnapshotStore(path: url)
        try store.save([LockSnapshot(id: "r", mode: .scheduled, endsAt: Date(timeIntervalSinceNow: 3600),
            isAllowlist: false, appliedDomains: ["x.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")])
        let controller = BlockController(snapshotStore: store, configStore: ConfigStore(path: tmpConfig()),
                                         appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true))
        controller.applyDecisionIfNeeded()
        XCTAssertFalse(store.load().isEmpty, "a not-yet-expired lock survives a daemon restart")
        try? FileManager.default.removeItem(at: url)
    }

    private func tmpConfig() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("config-boot.plist")
    }
}
