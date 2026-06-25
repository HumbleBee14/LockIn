import XCTest
@testable import LockInDaemonCore

final class PlaceholderTests: XCTestCase {
    func testVersionPresent() {
        XCTAssertFalse(LockInVersion.current.isEmpty)
    }
}
