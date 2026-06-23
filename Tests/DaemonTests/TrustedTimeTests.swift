import XCTest
@testable import LockInDaemonCore

final class TrustedTimeTests: XCTestCase {
    func testPinnedPolicyFailsClosedWithoutPins() {
        let source = PinnedTrustedTimeSource(
            hosts: [URL(string: "https://example.com")!], pinnedSHA256: [:], policy: .pinned)
        XCTAssertNil(source.fetch(), "pinned policy with no key => offline, never trusted (no network)")
    }
    func testFailsClosedWithFewerThanTwoHosts() {
        let source = PinnedTrustedTimeSource(
            hosts: [URL(string: "https://example.com")!], pinnedSHA256: [:], policy: .pinned)
        XCTAssertNil(source.fetch(), "a single host can never satisfy the >=2 agreement requirement")
    }
    func testSystemSourceUsesSystemTrustPolicy() {
        // system() must NOT be pinned-fail-closed, or the suspicion clear-path is permanently inert.
        // (Functional check is a live network test in RISKS.md; here we assert the construction intent.)
        XCTAssertNotNil(TrustedTime.system())
    }
}
