import XCTest
@testable import LockInDaemonCore

private final class FakeNow: NowProvider, @unchecked Sendable {
    var current: Date
    init(_ d: Date) { current = d }
    func now() -> Date { current }
}

// a rule that comes due while other locks are live must obey the same union cap the quick path does,
// and the daemon must say so instead of letting the hosts writer truncate the tail silently
@MainActor
final class ScheduledRuleCapTests: XCTestCase {
    private func paths(_ name: String) -> (URL, URL) {
        let t = FileManager.default.temporaryDirectory
        return (t.appendingPathComponent("\(name)-active.plist"), t.appendingPathComponent("\(name)-config.plist"))
    }

    private func cleanup(_ url: URL, _ cfg: URL) {
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    private func todayRule(id: String, sets: [String]) -> Rule {
        let wd = ((Calendar.current.dateComponents([.weekday], from: Date()).weekday! + 5) % 7) + 1
        return Rule(id: id, weekdays: [wd], startHour: 0, startMinute: 0,
                    endHour: 23, endMinute: 59, blockSetIds: sets, appBundleIds: [])
    }

    private let big = BlockSet(id: "big", name: "Big",
                               domains: (0..<BlockLimits.maxActiveDomains).map { "d\($0).com" },
                               appBundleIds: [], mode: .blocklist)
    private let adult = BlockSet(id: "a", name: "Adult", domains: ["adult.com"], appBundleIds: [], mode: .blocklist)

    func testDueRuleOverUnionCapIsSkippedSurfacedAndArmsOnceRoomFrees() throws {
        let (url, cfg) = paths("rulecap")
        try? FileManager.default.removeItem(at: url)
        defer { cleanup(url, cfg) }
        let cfgStore = ConfigStore(path: cfg)
        try cfgStore.save(ScheduleConfig(rules: [todayRule(id: "r1", sets: ["a"])], blockSets: [big, adult]))
        let clock = FakeNow(Date())
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: cfgStore,
                                appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true),
                                nowProvider: clock)

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["big"], durationSeconds: 600))
        c.reconcile()
        XCTAssertEqual(c.loadSnapshots().count, 1, "the due rule must not arm past the union cap")
        XCTAssertEqual(c.statusDTO().skippedScheduleTitles, ["Adult"], "and the skip must be surfaced")
        XCTAssertFalse(c.statusDTO().appliedDomains.contains("adult.com"))

        clock.current = clock.current.addingTimeInterval(700)   // the big quick lock expires
        c.reconcile()
        XCTAssertEqual(c.loadSnapshots().map(\.id), ["r1"], "with room freed the rule arms on the next tick")
        XCTAssertEqual(c.statusDTO().skippedScheduleTitles ?? [], [], "and the warning clears")
    }

    func testDueRuleWithinUnionCapStillArms() throws {
        let (url, cfg) = paths("rulecap-ok")
        try? FileManager.default.removeItem(at: url)
        defer { cleanup(url, cfg) }
        let cfgStore = ConfigStore(path: cfg)
        let social = BlockSet(id: "s", name: "Social", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        try cfgStore.save(ScheduleConfig(rules: [todayRule(id: "r1", sets: ["a"])], blockSets: [social, adult]))
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: cfgStore,
                                appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true))
        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["s"], durationSeconds: 600))
        c.reconcile()
        XCTAssertEqual(c.loadSnapshots().count, 2)
        XCTAssertNil(c.statusDTO().skippedScheduleTitles)
    }

    func testRegisterScheduleReportsFailedSave() throws {
        // a regular file where the config directory should be makes createDirectory throw
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-dir-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let (url, _) = paths("regsave")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url),
                                configStore: ConfigStore(path: blocker.appendingPathComponent("config.plist")),
                                appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true))
        XCTAssertFalse(c.registerSchedule(ScheduleConfig(rules: [])),
                       "a config the daemon could not persist must not be reported as accepted")
    }
}
