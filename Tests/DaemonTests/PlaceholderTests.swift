import XCTest
@testable import lockind

final class PlaceholderTests: XCTestCase {
    func testVersionPresent() {
        XCTAssertEqual(LockInVersion.current, "0.0.1")
    }
}
