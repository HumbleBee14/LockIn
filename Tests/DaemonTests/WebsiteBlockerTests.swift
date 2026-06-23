import XCTest
@testable import LockInDaemonCore

final class WebsiteBlockerTests: XCTestCase {
    func testExpandsDomainToCommonSubdomains() {
        let expanded = WebsiteBlocker.expand("youtube.com")
        XCTAssertTrue(expanded.contains("youtube.com"))
        XCTAssertTrue(expanded.contains("www.youtube.com"))
        XCTAssertTrue(expanded.contains("m.youtube.com"))
        XCTAssertTrue(expanded.contains("api.youtube.com"))
    }
    func testExpandStripsLeadingWww() {
        let expanded = WebsiteBlocker.expand("www.reddit.com")
        XCTAssertTrue(expanded.contains("reddit.com"))
        XCTAssertFalse(expanded.contains("www.www.reddit.com"))
    }
}
