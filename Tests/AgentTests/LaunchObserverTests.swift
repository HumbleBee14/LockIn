import XCTest
@testable import LockInAgentCore

final class LaunchObserverTests: XCTestCase {
    func testStartStopDoesNotCrash() {
        let o = LaunchObserver()
        o.start()
        o.stop()
    }
}
