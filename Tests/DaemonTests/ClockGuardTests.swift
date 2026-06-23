import XCTest
@testable import LockInDaemonCore

final class ClockGuardTests: XCTestCase {
    func testSystemBootSessionUUIDIsStableAndNonEmpty() {
        let b = SystemBootSession()
        let first = b.uuid
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, b.uuid, "boot session UUID must not change within a boot")
    }
    func testSystemMonotonicAdvances() {
        let m = SystemMonotonicClock()
        let a = m.seconds
        let b = m.seconds
        XCTAssertGreaterThanOrEqual(b, a)
    }
}
