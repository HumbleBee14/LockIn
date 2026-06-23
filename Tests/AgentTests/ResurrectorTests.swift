import XCTest
@testable import LockInAgentCore

final class ResurrectorTests: XCTestCase {
    func testDoesNotAttemptWhenDaemonAlive() {
        var pings = 0
        let r = Resurrector(daemonPing: { pings += 1; return true })
        r.tickIfBlockActive(true, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(pings, 1, "pings the daemon but takes no action when it is alive")
    }
    func testDoesNotAttemptWhenNoBlockActive() {
        var pings = 0
        let r = Resurrector(daemonPing: { pings += 1; return false })
        r.tickIfBlockActive(false, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(pings, 0, "no ping when no block is active")
    }
}
