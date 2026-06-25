import XCTest
@testable import LockInDaemonCore

final class WebsiteBlockerTests: XCTestCase {
    func testApexGetsWwwPair() {
        XCTAssertEqual(Set(WebsiteBlocker.expand("youtube.com")), ["youtube.com", "www.youtube.com"])
    }
    func testStripsLeadingWww() {
        XCTAssertEqual(Set(WebsiteBlocker.expand("www.reddit.com")), ["reddit.com", "www.reddit.com"])
    }
    func testNonNumberedSubdomainHasNoWwwVariant() {
        XCTAssertEqual(WebsiteBlocker.expand("cdn.servisehost.com"), ["cdn.servisehost.com"])
        XCTAssertEqual(WebsiteBlocker.expand("api.twitter.com"), ["api.twitter.com"])
    }
    func testNumberedPrefixEnumerates1To10() {
        let r = WebsiteBlocker.expand("cdn9.servisehost.com")
        XCTAssertEqual(r.count, 10)
        XCTAssertTrue(r.contains("cdn1.servisehost.com"))
        XCTAssertTrue(r.contains("cdn9.servisehost.com"))
        XCTAssertTrue(r.contains("cdn10.servisehost.com"))
        XCTAssertFalse(r.contains("cdn11.servisehost.com"))
    }
    func testNumberedPrefixNeedsBaseLetters() {
        // "9.x.com" has no letter base before the digit — don't enumerate
        XCTAssertEqual(WebsiteBlocker.expand("9.example.com"), ["9.example.com"])
    }
    func testExpansionOffIsOneToOne() {
        let domains = ["reddit.com", "cdn9.x.com", "www.youtube.com"]
        XCTAssertEqual(WebsiteBlocker.entries(for: domains, expand: false), domains)
    }
    func testHostsEntriesCeilingCaps() {
        let domains = (0..<(BlockLimits.maxHostsEntries + 5000)).map { "s\($0).com" }
        let entries = WebsiteBlocker.entries(for: domains, expand: false)
        XCTAssertEqual(entries.count, BlockLimits.maxHostsEntries)
    }
}
