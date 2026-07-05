import XCTest
@testable import LockInDaemonCore

final class DaemonStatusCompatTests: XCTestCase {
    // old-daemon JSON (no locks/appendTargetBlockSetId/engineDegraded) must decode (edge 14)
    func testDecodesStatusWithoutNewFields() throws {
        let json = """
        {"active":true,"source":"quick","blockSetTitle":"Social","isAllowlist":false,
         "endsAt":700000000,"appliedDomains":["x.com"],"appliedAppBundleIds":[],
         "pfApplied":true,"cleanupFailed":false}
        """
        let s = try JSONDecoder().decode(DaemonStatus.self, from: Data(json.utf8))
        XCTAssertNil(s.locks)
        XCTAssertNil(s.appendTargetBlockSetId)
        XCTAssertNil(s.engineDegraded)
    }

    func testRoundTripsNewFields() throws {
        let lock = ActiveLockInfo(id: "quick-1", title: "Social", source: "quick",
                                  endsAt: Date(timeIntervalSince1970: 100), isAllowlist: false,
                                  blockSetId: "b1", domainCount: 3)
        let s = DaemonStatus(active: true, source: "quick", blockSetTitle: "Social",
                             isAllowlist: false, endsAt: Date(), appliedDomains: ["x.com"],
                             nextTriggerDescription: nil, locks: [lock],
                             appendTargetBlockSetId: "b1", engineDegraded: false)
        let back = try JSONDecoder().decode(DaemonStatus.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.locks, [lock])
        XCTAssertEqual(back.appendTargetBlockSetId, "b1")
        XCTAssertEqual(back.engineDegraded, false)
        XCTAssertEqual(BlockLimits.maxActiveLocks, 10)
    }
}
