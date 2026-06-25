import XCTest
@testable import LockIn

@MainActor
final class ScheduleStoreTests: XCTestCase {
    func testAddAndRemoveRule() {
        let store = ScheduleStore(client: DaemonClient(), config: ScheduleConfig(rules: []))
        let r = Rule(id: "n", weekdays: [1], startHour: 22, startMinute: 0, endHour: 7, endMinute: 0,
                     blockSetIds: ["social"], appBundleIds: [])
        store.addRule(r)
        XCTAssertEqual(store.config.rules.count, 1)
        store.removeRule(id: "n")
        XCTAssertEqual(store.config.rules.count, 0)
    }

    func testCreateBlockSetWithFreeTitleAndMode() {
        let store = ScheduleStore(client: DaemonClient(), config: ScheduleConfig(rules: []))
        let set = store.createBlockSet(title: "Work Distractions", mode: .allowlist)
        XCTAssertTrue(store.config.blockSets.contains { $0.id == set.id })
        XCTAssertEqual(set.name, "Work Distractions")
        XCTAssertEqual(set.mode, .allowlist)
    }

    func testAddAppsDedupesAndRemove() {
        let store = ScheduleStore(client: DaemonClient(), config: ScheduleConfig(rules: []))
        let set = store.createBlockSet(title: "Focus")
        _ = store.addApps(["com.tinyspeck.slackmacgap", "com.hnc.Discord"], toBlockSet: set.id)
        _ = store.addApps(["com.hnc.Discord", "com.spotify.client"], toBlockSet: set.id)
        let apps = store.config.blockSets.first { $0.id == set.id }?.appBundleIds ?? []
        XCTAssertEqual(Set(apps), ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.spotify.client"],
                       "adding apps dedupes by bundle id")
        store.removeApp("com.hnc.Discord", fromBlockSet: set.id)
        XCTAssertFalse((store.config.blockSets.first { $0.id == set.id }?.appBundleIds ?? []).contains("com.hnc.Discord"))
    }

    func testAddAppsIgnoresEmptyBundleIds() {
        let store = ScheduleStore(client: DaemonClient(), config: ScheduleConfig(rules: []))
        let set = store.createBlockSet(title: "Focus")
        let outcome = store.addApps(["", "com.real.app"], toBlockSet: set.id)
        XCTAssertEqual(outcome.added, 1)
        XCTAssertEqual(store.config.blockSets.first { $0.id == set.id }?.appBundleIds, ["com.real.app"])
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
        let store = ScheduleStore(client: DaemonClient(), config: ScheduleConfig(rules: []))
        store.importDomains(into: "custom", from: "youtube.com\nyoutube.com\nreddit.com")
        let set = store.config.blockSets.first { $0.id == "custom" }
        XCTAssertEqual(set?.domains.sorted(), ["reddit.com", "youtube.com"])
    }
}
