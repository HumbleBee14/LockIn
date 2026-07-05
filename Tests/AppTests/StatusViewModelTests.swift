import XCTest
@testable import LockIn

@MainActor
final class StatusViewModelTests: XCTestCase {
    func testCountdownFormatsRemaining() {
        let vm = StatusViewModel(client: DaemonClient())
        let text = vm.countdown(to: Date(timeIntervalSinceNow: 3661))
        XCTAssertEqual(text, "1:01:01")
    }
    func testCountdownClampsToZero() {
        let vm = StatusViewModel(client: DaemonClient())
        XCTAssertEqual(vm.countdown(to: Date(timeIntervalSinceNow: -100)), "0:00:00")
    }

    private func lock(isAllowlist: Bool) -> ActiveLockInfo {
        ActiveLockInfo(id: UUID().uuidString, title: "t", source: "quick", endsAt: Date(),
                       isAllowlist: isAllowlist, blockSetId: UUID().uuidString, domainCount: 1)
    }

    private func status(active: Bool, isAllowlist: Bool, locks: [ActiveLockInfo]?) -> DaemonStatus {
        DaemonStatus(active: active, source: "quick", blockSetId: "set-1", blockSetTitle: "Work",
                     isAllowlist: isAllowlist, endsAt: Date(), appliedDomains: [],
                     nextTriggerDescription: nil, locks: locks)
    }

    // old daemon (locks == nil): falls back to the aggregate isAllowlist gate
    func testCanAddDomainsFallsBackWhenLocksNil() {
        let vm = StatusViewModel(client: DaemonClient())
        vm.status = status(active: true, isAllowlist: false, locks: nil)
        XCTAssertTrue(vm.canAddDomains)
        vm.status = status(active: true, isAllowlist: true, locks: nil)
        XCTAssertFalse(vm.canAddDomains)
    }

    // new daemon (locks present): any non-allowlist lock in the stack unlocks appending
    func testCanAddDomainsUsesPerLockMixedList() {
        let vm = StatusViewModel(client: DaemonClient())
        vm.status = status(active: true, isAllowlist: true, locks: [lock(isAllowlist: true), lock(isAllowlist: false)])
        XCTAssertTrue(vm.canAddDomains)
        vm.status = status(active: true, isAllowlist: false, locks: [lock(isAllowlist: true)])
        XCTAssertFalse(vm.canAddDomains)
    }

    // canStackLock requires an active lock AND a daemon that reports per-lock detail
    func testCanStackLockRequiresLocksArray() {
        let vm = StatusViewModel(client: DaemonClient())
        vm.status = status(active: true, isAllowlist: false, locks: nil)
        XCTAssertFalse(vm.canStackLock)
        vm.status = status(active: true, isAllowlist: false, locks: [lock(isAllowlist: false)])
        XCTAssertTrue(vm.canStackLock)
        vm.status = status(active: false, isAllowlist: false, locks: [lock(isAllowlist: false)])
        XCTAssertFalse(vm.canStackLock)
    }
}
