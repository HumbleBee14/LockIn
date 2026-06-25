import XCTest
@testable import LockInDaemonCore

final class LockSnapshotStoreTests: XCTestCase {
    private func tmp(_ n: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(n)
    }
    private func snap(_ id: String) -> LockSnapshot {
        LockSnapshot(id: id, mode: .scheduled, windowEnd: Date(timeIntervalSince1970: 100),
            duration: nil, isAllowlist: false, appliedDomains: ["x.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B",
            anchorWallTime: Date(timeIntervalSince1970: 0), trustedNowAtLastHeartbeat: Date(timeIntervalSince1970: 0),
            servedElapsedAtLastHeartbeat: 0, clockSuspicious: false, cumulativeDriftSeconds: 0, bootSessionUUID: "B")
    }

    func testSaveLoadRoundTrip() throws {
        let url = tmp("snap-roundtrip.plist"); try? FileManager.default.removeItem(at: url)
        let store = LockSnapshotStore(path: url)
        try store.save([snap("r1"), snap("r2")])
        XCTAssertEqual(store.load(), [snap("r1"), snap("r2")])
        try? FileManager.default.removeItem(at: url)
    }

    func testLoadsEmptyWhenMissing() {
        let url = tmp("snap-missing.plist"); try? FileManager.default.removeItem(at: url)
        XCTAssertEqual(LockSnapshotStore(path: url).load(), [])
    }

    func testFileIsMode600AfterSave() throws {
        let url = tmp("snap-perm.plist"); try? FileManager.default.removeItem(at: url)
        try LockSnapshotStore(path: url).save([snap("r")])
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try? FileManager.default.removeItem(at: url)
    }

    func testMigratesLegacyLockState() throws {
        let url = tmp("snap-legacy.plist"); try? FileManager.default.removeItem(at: url)
        let legacy = LockState(active: true, mode: .adHoc, windowEnd: nil, duration: 3600,
            anchorWallTime: Date(timeIntervalSince1970: 0), trustedNowAtLastHeartbeat: Date(timeIntervalSince1970: 0),
            servedElapsedAtLastHeartbeat: 120, clockSuspicious: false, bootSessionUUID: "B",
            appliedDomains: ["y.com"], appliedAppBundleIds: ["com.app"], appliedSettings: SettingsConfig(),
            isAllowlist: false, blockSetId: "b", blockSetTitle: "B", scheduleRuleId: nil)
        try Data(PropertyListEncoder().encode(legacy)).write(to: url)
        let loaded = LockSnapshotStore(path: url).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "quick")
        XCTAssertEqual(loaded.first?.duration, 3600)
        XCTAssertEqual(loaded.first?.servedElapsedAtLastHeartbeat, 120)
        try? FileManager.default.removeItem(at: url)
    }
}
