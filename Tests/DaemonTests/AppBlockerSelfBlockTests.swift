import XCTest
@testable import LockInDaemonCore

final class AppBlockerSelfBlockTests: XCTestCase {
    func testNeverMonitorsWhenOnlyOwnFamilyIsBlocked() {
        let b = AppBlocker()
        b.update(active: true, bundleIds: ["com.humblebee.lockin", "com.humblebee.lockin.agent",
                                          "com.humblebee.lockin.daemon", "com.humblebee.lockin.notifier"])
        XCTAssertFalse(b.isMonitoring(), "blocking only LockIn's own family must monitor nothing")
        b.update(active: false, bundleIds: [])
    }

    func testStillMonitorsRealTargetsAlongsideOwnFamily() {
        let b = AppBlocker()
        b.update(active: true, bundleIds: ["com.humblebee.lockin", "com.apple.Safari"])
        XCTAssertTrue(b.isMonitoring(), "a real target must still be monitored even when the list also names LockIn")
        b.update(active: false, bundleIds: [])
    }

    func testOwnFamilyExcludedFromNeverKillSet() {
        XCTAssertTrue(AppBlocker.neverKill.contains("com.humblebee.lockin"))
        XCTAssertTrue(AppBlocker.neverKill.contains("com.humblebee.lockin.daemon"))
    }
}
