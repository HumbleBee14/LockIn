import XCTest
@testable import LockInAgentCore

final class LaunchObserverTests: XCTestCase {
    func testTerminatesBlockedBundleWhenActive() {
        let o = LaunchObserver()
        o.updateSnapshot(BlockedAppSnapshot(active: true, bundleIds: ["com.tinyspeck.slackmacgap"]))
        XCTAssertTrue(o.shouldTerminate(bundleId: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(o.shouldTerminate(bundleId: "com.apple.Safari"))
    }
    func testDoesNotTerminateWhenInactive() {
        let o = LaunchObserver()
        o.updateSnapshot(BlockedAppSnapshot(active: false, bundleIds: ["com.tinyspeck.slackmacgap"]))
        XCTAssertFalse(o.shouldTerminate(bundleId: "com.tinyspeck.slackmacgap"))
    }
}
