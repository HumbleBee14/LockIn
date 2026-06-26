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
    // www pairing is ALWAYS applied, even with aggressive matching off
    func testWwwPairAlwaysOnEvenWhenExpandOff() {
        let e = WebsiteBlocker.entries(for: ["youtube.com"], expand: false)
        XCTAssertEqual(Set(e), ["youtube.com", "www.youtube.com"])
    }
    // aggressive matching OFF must NOT do the heavy CDN enumeration
    func testCdnEnumerationGatedByExpandFlag() {
        let off = WebsiteBlocker.entries(for: ["cdn9.x.com"], expand: false)
        XCTAssertEqual(off, ["cdn9.x.com"], "off: no CDN enumeration")
        let on = WebsiteBlocker.entries(for: ["cdn9.x.com"], expand: true)
        XCTAssertTrue(on.contains("cdn1.x.com") && on.contains("cdn10.x.com"), "on: CDN enumeration")
    }
    func testHostsEntriesCeilingCaps() {
        let domains = (0..<(BlockLimits.maxHostsEntries + 5000)).map { "s\($0).com" }
        let entries = WebsiteBlocker.entries(for: domains, expand: false)
        XCTAssertEqual(entries.count, BlockLimits.maxHostsEntries)
    }

    private func hosts(_ block: String) -> String {
        "127.0.0.1\tlocalhost\n# BEGIN SELFCONTROL BLOCK\n\(block)\n# END SELFCONTROL BLOCK\n"
    }

    func testBlockPresentWhenEntryInSection() {
        let contents = hosts("0.0.0.0\tyoutube.com")
        XCTAssertTrue(WebsiteBlocker.blockPresent(in: contents, entries: ["youtube.com"]))
    }

    // partial-tamper integrity: a full block is intact; deleting most or a sampled entry is not
    func testSectionIntactWhenAllPresent() {
        let block = ["a.com", "b.com", "c.com", "d.com"].map { "0.0.0.0\t\($0)" }.joined(separator: "\n")
        XCTAssertTrue(WebsiteBlocker.sectionIntact(in: hosts(block), entries: ["a.com", "b.com", "c.com", "d.com"]))
    }
    func testSectionNotIntactAfterBulkDeletion() {
        let block = "0.0.0.0\ta.com"   // 3 of 4 lines deleted
        XCTAssertFalse(WebsiteBlocker.sectionIntact(in: hosts(block), entries: ["a.com", "b.com", "c.com", "d.com"]))
    }
    func testSectionNotIntactWhenProbedEntryMissing() {
        // same line count via a junk line, but a sampled (middle) entry was swapped out
        let block = ["0.0.0.0\ta.com", "0.0.0.0\tJUNK.com", "0.0.0.0\tc.com"].joined(separator: "\n")
        XCTAssertFalse(WebsiteBlocker.sectionIntact(in: hosts(block), entries: ["a.com", "b.com", "c.com"]))
    }
    func testBlockAbsentWhenNoMarkers() {
        let contents = "127.0.0.1\tlocalhost\n"
        XCTAssertFalse(WebsiteBlocker.blockPresent(in: contents, entries: ["youtube.com"]))
    }
    func testBlockAbsentWhenSectionEmpty() {
        // stale/empty marker block must NOT pass — markers alone aren't proof
        let contents = hosts("")
        XCTAssertFalse(WebsiteBlocker.blockPresent(in: contents, entries: ["youtube.com"]))
    }
    func testBlockAbsentWhenDomainOutsideSection() {
        let contents = "0.0.0.0\tyoutube.com\n# BEGIN SELFCONTROL BLOCK\n0.0.0.0\tother.com\n# END SELFCONTROL BLOCK\n"
        XCTAssertFalse(WebsiteBlocker.blockPresent(in: contents, entries: ["youtube.com"]))
    }
    func testBlockAbsentWhenNoEntriesRequested() {
        XCTAssertFalse(WebsiteBlocker.blockPresent(in: hosts("0.0.0.0\tx.com"), entries: []))
    }
}
