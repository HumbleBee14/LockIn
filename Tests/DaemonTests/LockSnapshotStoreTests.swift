import XCTest
@testable import LockInDaemonCore

final class LockSnapshotStoreTests: XCTestCase {
    private func tmp(_ n: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(n)
    }
    private func snap(_ id: String) -> LockSnapshot {
        LockSnapshot(id: id, mode: .scheduled, endsAt: Date(timeIntervalSince1970: 100),
            isAllowlist: false, appliedDomains: ["x.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")
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
}
