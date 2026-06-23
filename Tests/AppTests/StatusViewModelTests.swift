import XCTest
@testable import LockIn

@MainActor
final class StatusViewModelTests: XCTestCase {
    func testCountdownFormatsRemaining() {
        let vm = StatusViewModel(client: DaemonClient())
        let text = vm.countdown(to: Date(timeIntervalSinceNow: 3661))
        XCTAssertEqual(text, "1h 1m")
    }
    func testCountdownClampsToZero() {
        let vm = StatusViewModel(client: DaemonClient())
        XCTAssertEqual(vm.countdown(to: Date(timeIntervalSinceNow: -100)), "0h 0m")
    }
}
