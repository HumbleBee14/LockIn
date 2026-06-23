import XCTest
@testable import LockInDaemonCore

final class TrustedTimeTests: XCTestCase {
    func testFailsClosedWithoutPins() {
        let source = PinnedTrustedTimeSource(
            hosts: [URL(string: "https://example.com")!], pinnedSHA256: [:])
        XCTAssertNil(source.fetch(), "no pinned key => treated as offline, never trusted")
    }
    func testFailsClosedWithFewerThanTwoHosts() {
        let source = PinnedTrustedTimeSource(
            hosts: [URL(string: "https://example.com")!],
            pinnedSHA256: ["example.com": ["fakepin"]])
        XCTAssertNil(source.fetch(), "a single host can never satisfy the >=2 agreement requirement")
    }
    func testSystemSourceFailsClosedUntilPinsFilled() {
        XCTAssertNil(TrustedTime.system().fetch(),
            "system source ships with empty pins => offline until the pinning spike fills keys")
    }
}
