import XCTest
@testable import LockInAgentCore

final class SnapshotTests: XCTestCase {
    func testSnapshotRoundTrips() throws {
        let s = BlockedAppSnapshot(active: true, bundleIds: ["com.tinyspeck.slackmacgap"])
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(BlockedAppSnapshot.self, from: data), s)
    }
}
