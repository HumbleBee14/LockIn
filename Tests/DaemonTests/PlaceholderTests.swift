import XCTest
@testable import LockInDaemonCore

final class PlaceholderTests: XCTestCase {
    func testVersionPresent() {
        XCTAssertEqual(LockInVersion.current, "0.0.1")
    }
}
