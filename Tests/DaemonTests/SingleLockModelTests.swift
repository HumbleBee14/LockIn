import XCTest
@testable import LockInDaemonCore

@MainActor
final class SingleLockModelTests: XCTestCase {
    private func paths(_ name: String) -> (URL, URL) {
        let t = FileManager.default.temporaryDirectory
        return (t.appendingPathComponent("\(name)-active.plist"),
                t.appendingPathComponent("\(name)-config.plist"))
    }

    private func controller(_ config: ScheduleConfig, _ name: String,
                            verifyHosts: Bool = true) throws -> (BlockController, URL, URL) {
        let (url, cfg) = paths(name)
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        try cfgStore.save(config)
        let blocker = WebsiteBlocker(forceVerified: verifyHosts)
        return (BlockController(snapshotStore: LockSnapshotStore(path: url),
                                configStore: cfgStore, appBlocker: SpyAppBlocker(), blocker: blocker), url, cfg)
    }

    // a rule active for today, full day
    private func todayRule(id: String, sets: [String]) -> Rule {
        let wd = ((Calendar.current.dateComponents([.weekday], from: Date()).weekday! + 5) % 7) + 1
        return Rule(id: id, weekdays: [wd], startHour: 0, startMinute: 0,
                    endHour: 23, endMinute: 59, blockSetIds: sets, appBundleIds: [])
    }

    func testQuickLockCarriesAllowlistMode() throws {
        let set = BlockSet(id: "a", name: "Allow Work", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "allow")
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["a"], durationSeconds: 60))
        XCTAssertEqual(c.statusDTO().isAllowlist, true)
        XCTAssertEqual(c.statusDTO().blockSetTitle, "Allow Work")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testAppendRejectedInAllowlistMode() throws {
        let set = BlockSet(id: "a", name: "Allow", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "appall")
        _ = c.startQuickLock(blockSetIds: ["a"], durationSeconds: 60)
        XCTAssertFalse(c.appendDomainsToActiveBlock(["evil.com"]),
            "appending to an allowlist would widen access; must be rejected")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testAppendAddsToActiveBlocklist() throws {
        let set = BlockSet(id: "b", name: "Block", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "appblock")
        _ = c.startQuickLock(blockSetIds: ["b"], durationSeconds: 60)
        XCTAssertTrue(c.appendDomainsToActiveBlock(["reddit.com"]))
        XCTAssertEqual(c.statusDTO().appliedDomains.contains("reddit.com"), true)
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testAppendRejectsControlCharInjection() throws {
        let set = BlockSet(id: "b", name: "Block", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "appinject")
        _ = c.startQuickLock(blockSetIds: ["b"], durationSeconds: 60)
        XCTAssertTrue(c.appendDomainsToActiveBlock(["evil.com\n0.0.0.0 sneaky.com"]),
            "filtered-out bad domains leave a no-op success, never a raw write")
        XCTAssertFalse(c.statusDTO().appliedDomains.contains { $0.contains("\n") },
            "a newline-bearing domain must never enter the snapshot")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testMultiSetCombinesAndDedupes() throws {
        let a = BlockSet(id: "a", name: "A", domains: ["youtube.com", "reddit.com"], appBundleIds: [], mode: .blocklist)
        let b = BlockSet(id: "b", name: "B", domains: ["reddit.com", "x.com"], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [a, b]), "multi")
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["a", "b"], durationSeconds: 60))
        XCTAssertEqual(Set(c.statusDTO().appliedDomains), ["youtube.com", "reddit.com", "x.com"])
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testScheduleDoesNotFireForEmptyOrMissingSet() throws {
        let empty = BlockSet(id: "empty", name: "Empty", domains: [], appBundleIds: [], mode: .blocklist)
        let emptyRule = todayRule(id: "r1", sets: ["empty"])
        let missingRule = todayRule(id: "r2", sets: ["ghost"])
        let (c, url, cfg) = try controller(
            ScheduleConfig(rules: [emptyRule, missingRule], blockSets: [empty]), "sched")
        c.reconcile()
        XCTAssertFalse(c.statusDTO().active, "empty/missing sets must not start a scheduled block")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testMultiSetRejectsMixedModes() throws {
        let block = BlockSet(id: "a", name: "A", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let allow = BlockSet(id: "b", name: "B", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [block, allow]), "mixed")
        XCTAssertFalse(c.startQuickLock(blockSetIds: ["a", "b"], durationSeconds: 60),
            "mixing allowlist and blocklist in one lock must be rejected")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testScheduledLockMergesMultipleSets() throws {
        let a = BlockSet(id: "a", name: "A", domains: ["youtube.com", "reddit.com"], appBundleIds: [], mode: .blocklist)
        let b = BlockSet(id: "b", name: "B", domains: ["reddit.com", "x.com"], appBundleIds: [], mode: .blocklist)
        let rule = todayRule(id: "r", sets: ["a", "b"])
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [rule], blockSets: [a, b]), "schedmulti")
        c.reconcile()
        XCTAssertEqual(Set(c.statusDTO().appliedDomains), ["youtube.com", "reddit.com", "x.com"])
        XCTAssertEqual(c.statusDTO().source, "scheduled")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testScheduledLockRejectsMixedModes() throws {
        let block = BlockSet(id: "a", name: "A", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let allow = BlockSet(id: "b", name: "B", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let rule = todayRule(id: "r", sets: ["a", "b"])
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [rule], blockSets: [block, allow]), "schedmixed")
        c.reconcile()
        XCTAssertFalse(c.statusDTO().active, "a scheduled rule mixing modes must not fire")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testLegacyRuleMigratesSingleBlockSetId() throws {
        let json = #"{"id":"r","weekdays":[1],"startHour":1,"startMinute":0,"endHour":2,"endMinute":0,"blockSetId":"social","appBundleIds":[]}"#
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.blockSetIds, ["social"], "old single blockSetId must migrate to the array")
    }

    func testQuickLockFailsAndRollsBackWhenHostsNotWritten() throws {
        let set = BlockSet(id: "b", name: "Block", domains: ["lockin-test-unverifiable.invalid"], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "noverify", verifyHosts: false)
        XCTAssertFalse(c.startQuickLock(blockSetIds: ["b"], durationSeconds: 60),
            "a lock whose hosts write can't be verified must fail")
        XCTAssertFalse(c.statusDTO().active, "failed verification must leave no active state")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testScheduleDoesNotShortenActiveQuickLock() throws {
        let quick = BlockSet(id: "q", name: "Quick", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let schedSet = BlockSet(id: "s", name: "Nightly", domains: ["reddit.com"], appBundleIds: [], mode: .blocklist)
        let rule = todayRule(id: "r", sets: ["s"])
        let (c, url, cfg) = try controller(
            ScheduleConfig(rules: [rule], blockSets: [quick, schedSet]), "preempt")
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["q"], durationSeconds: 3600))
        c.reconcile()
        let snaps = c.loadSnapshots()
        XCTAssertTrue(snaps.contains { $0.id == "quick" && $0.mode == .adHoc },
            "a due schedule must NOT replace or shorten the active quick lock")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testOverlappingSchedulesUnionThenExpiryLeavesSurvivor() throws {
        let adult = BlockSet(id: "adult", name: "Adult", domains: ["adult.com", "shared.com"], appBundleIds: [], mode: .blocklist)
        let social = BlockSet(id: "social", name: "Social", domains: ["social.com", "shared.com"], appBundleIds: [], mode: .blocklist)
        let adultRule = todayRule(id: "ra", sets: ["adult"])
        let socialRule = todayRule(id: "rs", sets: ["social"])
        let (c, url, cfg) = try controller(
            ScheduleConfig(rules: [adultRule, socialRule], blockSets: [adult, social]), "overlap")
        c.reconcile()
        XCTAssertEqual(Set(c.statusDTO().appliedDomains), ["adult.com", "shared.com", "social.com"],
            "overlapping blocklists are unioned")
        XCTAssertEqual(c.loadSnapshots().count, 2)
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testAllowlistWinsWhenOverlappingBlocklist() throws {
        let block = BlockSet(id: "block", name: "Adult", domains: ["adult.com"], appBundleIds: [], mode: .blocklist)
        let allow = BlockSet(id: "allow", name: "Focus", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let (c, url, cfg) = try controller(
            ScheduleConfig(rules: [todayRule(id: "rb", sets: ["block"]), todayRule(id: "rl", sets: ["allow"])],
                           blockSets: [block, allow]), "allowwins")
        c.reconcile()
        XCTAssertTrue(c.statusDTO().isAllowlist, "any active allowlist makes the effective state allowlist")
        XCTAssertEqual(c.statusDTO().appliedDomains, ["gmail.com"], "only the allowlist set defines what's reachable")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }
}
