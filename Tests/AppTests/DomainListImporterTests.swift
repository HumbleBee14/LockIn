import XCTest
@testable import LockIn

final class DomainListImporterTests: XCTestCase {
    func testPlainList() {
        let r = DomainListImporter.parse("youtube.com\nreddit.com\n")
        XCTAssertEqual(r, ["youtube.com", "reddit.com"])
    }
    func testHostsFile() {
        let r = DomainListImporter.parse("# title\n0.0.0.0 ads.example.com\n127.0.0.1 tracker.net\n")
        XCTAssertTrue(r.contains("ads.example.com"))
        XCTAssertTrue(r.contains("tracker.net"))
    }
    func testAdBlockFilter() {
        let r = DomainListImporter.parse("||doubleclick.net^\n||ads.example.com^$third-party\n")
        XCTAssertTrue(r.contains("doubleclick.net"))
        XCTAssertTrue(r.contains("ads.example.com"))
    }
    func testCSV() {
        let r = DomainListImporter.parse("domain,category\nfacebook.com,social\ntiktok.com,social\n")
        XCTAssertTrue(r.contains("facebook.com"))
        XCTAssertTrue(r.contains("tiktok.com"))
        XCTAssertFalse(r.contains("domain"))
    }
    func testStripsSchemePathPortAndDedupes() {
        let r = DomainListImporter.parse("https://www.reddit.com/r/all\nreddit.com:443\nreddit.com\n")
        XCTAssertEqual(r.filter { $0 == "reddit.com" }.count, 1)
        XCTAssertTrue(r.contains("www.reddit.com"))
    }
    func testRejectsNonDomainTokens() {
        let r = DomainListImporter.parse("not-a-domain\nlocalhost\n")
        XCTAssertTrue(r.isEmpty)
    }
    func testRejectsMalformedDomains() {
        XCTAssertFalse(DomainListImporter.isValidDomain("...."))
        XCTAssertFalse(DomainListImporter.isValidDomain("a.b c.d"))
        XCTAssertFalse(DomainListImporter.isValidDomain("-bad.com"))
        XCTAssertFalse(DomainListImporter.isValidDomain("bad-.com"))
        XCTAssertFalse(DomainListImporter.isValidDomain("example.123"))
        XCTAssertTrue(DomainListImporter.isValidDomain("sub.example.co.uk"))
        XCTAssertTrue(DomainListImporter.isValidDomain("cdn9.servisehost.com"))
    }
    func testStripsTrailingDotAndUserInfo() {
        XCTAssertEqual(DomainListImporter.normalize("reddit.com."), "reddit.com")
        XCTAssertEqual(DomainListImporter.normalize("user@reddit.com"), "reddit.com")
    }
    func testExportRoundTrips() {
        let domains = ["youtube.com", "reddit.com", "x.com"]
        let text = DomainListImporter.export(domains)
        XCTAssertEqual(Set(DomainListImporter.parse(text)), Set(domains))
    }
}
