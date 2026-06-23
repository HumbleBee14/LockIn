import XCTest
@testable import LockInDaemonCore

final class CodeSigningAuthTests: XCTestCase {
    func testRejectsConnectionFromUnsignedClient() {
        let listener = DaemonListener()
        let token = audit_token_t()
        XCTAssertFalse(listener.isClientValid(token),
                       "A zeroed/unsigned audit token must be rejected")
    }
}
