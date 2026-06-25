import XCTest
@testable import LockInDaemonCore

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
        let guard_ = ClockGuard(wall: FakeWallClock(Date()), monotonic: FakeMonotonicClock(0),
                                boot: FakeBootSession("B"), trusted: FakeTrustedTimeSource(nil))
        // tests can't write /etc/hosts or load pf — force verification so we exercise state/merge logic
        let blocker = WebsiteBlocker(forceVerified: verifyHosts)
        return (BlockController(store: LockStateStore(path: url), clockGuard: guard_,
                                configStore: cfgStore, agentBridge: SpyAgentBridge(), blocker: blocker), url, cfg)
    }

    func testQuickLockCarriesAllowlistMode() throws {
        let set = BlockSet(id: "a", name: "Allow Work", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "allow")
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["a"], durationSeconds: 60))
        XCTAssertEqual(c.currentStatus()?.isAllowlist, true)
        XCTAssertEqual(c.currentStatus()?.blockSetTitle, "Allow Work")
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
        XCTAssertEqual(c.currentStatus()?.appliedDomains.contains("reddit.com"), true)
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testMultiSetCombinesAndDedupes() throws {
        let a = BlockSet(id: "a", name: "A", domains: ["youtube.com", "reddit.com"], appBundleIds: [], mode: .blocklist)
        let b = BlockSet(id: "b", name: "B", domains: ["reddit.com", "x.com"], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [a, b]), "multi")
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["a", "b"], durationSeconds: 60))
        let applied = Set(c.currentStatus()?.appliedDomains ?? [])
        XCTAssertEqual(applied, ["youtube.com", "reddit.com", "x.com"])
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testScheduleDoesNotFireForEmptyOrMissingSet() throws {
        let cal = Calendar.current
        let wd = ((cal.dateComponents([.weekday], from: Date()).weekday! + 5) % 7) + 1
        let emptyRule = Rule(id: "r1", weekdays: [wd], startHour: 0, startMinute: 0,
                             endHour: 23, endMinute: 59, blockSetIds: ["empty"], appBundleIds: [])
        let missingRule = Rule(id: "r2", weekdays: [wd], startHour: 0, startMinute: 0,
                               endHour: 23, endMinute: 59, blockSetIds: ["ghost"], appBundleIds: [])
        let empty = BlockSet(id: "empty", name: "Empty", domains: [], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [emptyRule, missingRule], blockSets: [empty]), "sched")
        c.startScheduled(rule: emptyRule, windowEnd: Date().addingTimeInterval(3600))
        XCTAssertNil(c.currentStatus(), "empty set must not start a scheduled block")
        c.startScheduled(rule: missingRule, windowEnd: Date().addingTimeInterval(3600))
        XCTAssertNil(c.currentStatus(), "missing set must not start a scheduled block")
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
        let rule = Rule(id: "r", weekdays: [1,2,3,4,5,6,7], startHour: 0, startMinute: 0,
                        endHour: 23, endMinute: 59, blockSetIds: ["a", "b"], appBundleIds: [])
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [rule], blockSets: [a, b]), "schedmulti")
        c.startScheduled(rule: rule, windowEnd: Date().addingTimeInterval(3600))
        XCTAssertEqual(Set(c.currentStatus()?.appliedDomains ?? []), ["youtube.com", "reddit.com", "x.com"])
        XCTAssertEqual(c.currentStatus()?.mode, .scheduled)
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testScheduledLockRejectsMixedModes() throws {
        let block = BlockSet(id: "a", name: "A", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let allow = BlockSet(id: "b", name: "B", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let rule = Rule(id: "r", weekdays: [1,2,3,4,5,6,7], startHour: 0, startMinute: 0,
                        endHour: 23, endMinute: 59, blockSetIds: ["a", "b"], appBundleIds: [])
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [rule], blockSets: [block, allow]), "schedmixed")
        c.startScheduled(rule: rule, windowEnd: Date().addingTimeInterval(3600))
        XCTAssertNil(c.currentStatus(), "a scheduled rule mixing modes must not fire")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testLegacyRuleMigratesSingleBlockSetId() throws {
        let json = #"{"id":"r","weekdays":[1],"startHour":1,"startMinute":0,"endHour":2,"endMinute":0,"blockSetId":"social","appBundleIds":[]}"#
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.blockSetIds, ["social"], "old single blockSetId must migrate to the array")
    }

    func testQuickLockFailsAndRollsBackWhenHostsNotWritten() throws {
        let set = BlockSet(id: "b", name: "Block", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "noverify", verifyHosts: false)
        XCTAssertFalse(c.startQuickLock(blockSetIds: ["b"], durationSeconds: 60),
            "a lock whose hosts write can't be verified must fail")
        XCTAssertNil(c.currentStatus(), "failed verification must leave no active state — UI never shows the lock screen")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testScheduledLockRollsBackWhenHostsNotWritten() throws {
        let set = BlockSet(id: "s", name: "Nightly", domains: ["reddit.com"], appBundleIds: [], mode: .blocklist)
        let rule = Rule(id: "r", weekdays: [1,2,3,4,5,6,7], startHour: 0, startMinute: 0,
                        endHour: 23, endMinute: 59, blockSetIds: ["s"], appBundleIds: [])
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [rule], blockSets: [set]), "schednoverify", verifyHosts: false)
        c.startScheduled(rule: rule, windowEnd: Date().addingTimeInterval(3600))
        XCTAssertNil(c.currentStatus(), "a scheduled lock that can't verify its hosts write must not activate")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testSchedulePreemptsActiveQuickLock() throws {
        let quick = BlockSet(id: "q", name: "Quick", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let schedSet = BlockSet(id: "s", name: "Nightly", domains: ["reddit.com"], appBundleIds: [], mode: .blocklist)
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.hour, .minute, .weekday], from: Date())
        let wd = ((nowComps.weekday! + 5) % 7) + 1
        let rule = Rule(id: "r", weekdays: [wd], startHour: 0, startMinute: 0,
                        endHour: 23, endMinute: 59, blockSetIds: ["s"], appBundleIds: [])
        let (c, url, cfg) = try controller(
            ScheduleConfig(rules: [rule], blockSets: [quick, schedSet]), "preempt")
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["q"], durationSeconds: 3600))
        XCTAssertEqual(c.currentStatus()?.mode, .adHoc)
        c.applyDecisionIfNeeded(timeResolved: true, calendar: cal)
        XCTAssertEqual(c.currentStatus()?.mode, .scheduled,
            "a due schedule must preempt an active quick lock")
        XCTAssertEqual(c.currentStatus()?.scheduleRuleId, "r")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }
}
