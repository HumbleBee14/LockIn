import XCTest
@testable import LockIn

final class DaemonClientTests: XCTestCase {
    func testDaemonStatusRoundTrips() throws {
        let s = DaemonStatus(active: true, source: "scheduled", blockSetTitle: "Nightly",
            isAllowlist: false, endsAt: Date(timeIntervalSince1970: 100), appliedDomains: ["x.com"],
            nextTriggerDescription: nil)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(DaemonStatus.self, from: data)
        XCTAssertEqual(s, back)
    }
}
