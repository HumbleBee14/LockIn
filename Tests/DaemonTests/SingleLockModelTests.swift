import XCTest
@testable import LockInDaemonCore

final class SingleLockModelTests: XCTestCase {
    private func paths(_ name: String) -> (URL, URL) {
        let t = FileManager.default.temporaryDirectory
        return (t.appendingPathComponent("\(name)-active.plist"),
                t.appendingPathComponent("\(name)-config.plist"))
    }

    private func controller(_ config: ScheduleConfig, _ name: String) throws -> (BlockController, URL, URL) {
        let (url, cfg) = paths(name)
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        try cfgStore.save(config)
        let guard_ = ClockGuard(wall: FakeWallClock(Date()), monotonic: FakeMonotonicClock(0),
                                boot: FakeBootSession("B"), trusted: FakeTrustedTimeSource(nil))
        return (BlockController(store: LockStateStore(path: url), clockGuard: guard_,
                                configStore: cfgStore, agentBridge: SpyAgentBridge()), url, cfg)
    }

    func testQuickLockCarriesAllowlistMode() throws {
        let set = BlockSet(id: "a", name: "Allow Work", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "allow")
        XCTAssertTrue(c.startQuickLock(blockSetId: "a", durationSeconds: 60))
        XCTAssertEqual(c.currentStatus()?.isAllowlist, true)
        XCTAssertEqual(c.currentStatus()?.blockSetTitle, "Allow Work")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testAppendRejectedInAllowlistMode() throws {
        let set = BlockSet(id: "a", name: "Allow", domains: ["gmail.com"], appBundleIds: [], mode: .allowlist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "appall")
        _ = c.startQuickLock(blockSetId: "a", durationSeconds: 60)
        XCTAssertFalse(c.appendDomainsToActiveBlock(["evil.com"]),
            "appending to an allowlist would widen access; must be rejected")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testAppendAddsToActiveBlocklist() throws {
        let set = BlockSet(id: "b", name: "Block", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let (c, url, cfg) = try controller(ScheduleConfig(rules: [], blockSets: [set]), "appblock")
        _ = c.startQuickLock(blockSetId: "b", durationSeconds: 60)
        XCTAssertTrue(c.appendDomainsToActiveBlock(["reddit.com"]))
        XCTAssertEqual(c.currentStatus()?.appliedDomains.contains("reddit.com"), true)
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testSchedulePreemptsActiveQuickLock() throws {
        let quick = BlockSet(id: "q", name: "Quick", domains: ["youtube.com"], appBundleIds: [], mode: .blocklist)
        let schedSet = BlockSet(id: "s", name: "Nightly", domains: ["reddit.com"], appBundleIds: [], mode: .blocklist)
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.hour, .minute, .weekday], from: Date())
        let wd = ((nowComps.weekday! + 5) % 7) + 1
        let rule = Rule(id: "r", weekdays: [wd], startHour: 0, startMinute: 0,
                        endHour: 23, endMinute: 59, blockSetId: "s", appBundleIds: [])
        let (c, url, cfg) = try controller(
            ScheduleConfig(rules: [rule], blockSets: [quick, schedSet]), "preempt")
        XCTAssertTrue(c.startQuickLock(blockSetId: "q", durationSeconds: 3600))
        XCTAssertEqual(c.currentStatus()?.mode, .adHoc)
        c.applyDecisionIfNeeded(timeResolved: true, calendar: cal)
        XCTAssertEqual(c.currentStatus()?.mode, .scheduled,
            "a due schedule must preempt an active quick lock")
        XCTAssertEqual(c.currentStatus()?.scheduleRuleId, "r")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }
}
