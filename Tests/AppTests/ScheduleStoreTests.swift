import XCTest
@testable import LockIn

@MainActor
final class ScheduleStoreTests: XCTestCase {
    func testAddAndRemoveRule() {
        let store = ScheduleStore(client: DaemonClient())
        let r = Rule(id: "n", weekdays: [1], startHour: 22, startMinute: 0, endHour: 7, endMinute: 0,
                     blockSetId: "social", appBundleIds: [])
        store.addRule(r)
        XCTAssertEqual(store.config.rules.count, 1)
        store.removeRule(id: "n")
        XCTAssertEqual(store.config.rules.count, 0)
    }

    func testImportSocialPresetAddsDomains() {
        let store = ScheduleStore(client: DaemonClient())
        store.importPreset(.social)
        XCTAssertTrue(store.config.blockSets.contains { $0.id == "social" && !$0.domains.isEmpty })
    }

    func testParseDomainListStripsHostsAndComments() {
        let text = """
        # blocklist
        0.0.0.0 ads.example.com
        https://www.reddit.com/r/all
        youtube.com
        not-a-domain
        """
        let parsed = ScheduleStore.parseDomainList(text)
        XCTAssertTrue(parsed.contains("ads.example.com"))
        XCTAssertTrue(parsed.contains("www.reddit.com"))
        XCTAssertTrue(parsed.contains("youtube.com"))
        XCTAssertFalse(parsed.contains("not-a-domain"))
    }

    func testImportDomainsMergesWithoutDuplicates() {
        let store = ScheduleStore(client: DaemonClient())
        store.importDomains(into: "custom", from: "youtube.com\nyoutube.com\nreddit.com")
        let set = store.config.blockSets.first { $0.id == "custom" }
        XCTAssertEqual(set?.domains.sorted(), ["reddit.com", "youtube.com"])
    }
}
