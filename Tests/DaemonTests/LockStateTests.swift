import XCTest
@testable import LockInDaemonCore

final class LockStateTests: XCTestCase {
    func testRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-test.plist")
        let store = LockStateStore(path: url)
        let s = LockState(active: true, mode: .scheduled, windowEnd: Date(timeIntervalSince1970: 1000),
            duration: nil, anchorWallTime: Date(timeIntervalSince1970: 100),
            trustedNowAtLastHeartbeat: Date(timeIntervalSince1970: 100),
            servedElapsedAtLastHeartbeat: 0, clockSuspicious: false,
            bootSessionUUID: "ABC", appliedDomains: ["youtube.com"], appliedAppBundleIds: [])
        try store.save(s)
        XCTAssertEqual(store.load(), s)
        try? FileManager.default.removeItem(at: url)
    }
    func testFileIsMode600AfterSave() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-perm.plist")
        let store = LockStateStore(path: url)
        try store.save(LockState(active: true, mode: .adHoc, windowEnd: nil, duration: 3600,
            anchorWallTime: Date(), trustedNowAtLastHeartbeat: Date(),
            servedElapsedAtLastHeartbeat: 0, clockSuspicious: false,
            bootSessionUUID: "X", appliedDomains: [], appliedAppBundleIds: []))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try? FileManager.default.removeItem(at: url)
    }
}
