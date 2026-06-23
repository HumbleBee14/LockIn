import XCTest
@testable import LockInAgentCore

final class AgentListenerTests: XCTestCase {
    func testRejectsConnectionFromUnsignedClient() {
        let listener = AgentListener(observer: LaunchObserver())
        let token = audit_token_t()
        XCTAssertFalse(listener.isClientValid(token),
                       "a zeroed/unsigned audit token must be rejected")
    }

    func testUpdateSnapshotForwardsToObserver() {
        let observer = LaunchObserver()
        let xpc = AgentXPC(observer: observer)
        let data = try! JSONEncoder().encode(BlockedAppSnapshot(active: true, bundleIds: ["com.x.y"]))
        let exp = expectation(description: "reply")
        xpc.updateSnapshot(data) { ok in XCTAssertTrue(ok); exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertTrue(observer.shouldTerminate(bundleId: "com.x.y"))
    }
}
