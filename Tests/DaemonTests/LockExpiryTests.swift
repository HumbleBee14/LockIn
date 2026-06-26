import XCTest
@testable import LockInDaemonCore

// the unified clock: a fixed instant the test controls, standing in for online-or-system UTC
private final class FakeNow: NowProvider {
    var instant: Date
    init(_ d: Date) { instant = d }
    func now() -> Date { instant }
}

@MainActor
final class LockExpiryTests: XCTestCase {
    private func paths(_ name: String) -> (URL, URL) {
        let t = FileManager.default.temporaryDirectory
        return (t.appendingPathComponent("\(name)-active.plist"),
                t.appendingPathComponent("\(name)-config.plist"))
    }

    private func make(_ name: String, now: FakeNow) throws -> (BlockController, URL, URL) {
        let (url, cfg) = paths(name)
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        try cfgStore.save(ScheduleConfig(rules: []))
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: cfgStore,
                                appBlocker: SpyAppBlocker(), blocker: WebsiteBlocker(forceVerified: true),
                                nowProvider: now)
        return (c, url, cfg)
    }

    private func snap(id: String, mode: BlockMode, endsAt: Date) -> LockSnapshot {
        LockSnapshot(id: id, mode: mode, endsAt: endsAt, isAllowlist: false,
            appliedDomains: ["youtube.com"], appliedAppBundleIds: [], appliedSettings: SettingsConfig(),
            blockSetId: "b", blockSetTitle: "Block")
    }

    func testLiftsWhenNowPastEndsAt() throws {
        let now = FakeNow(Date(timeIntervalSince1970: 5000))
        let (c, url, cfg) = try make("expire-past", now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        try LockSnapshotStore(path: url).save([snap(id: "quick", mode: .adHoc,
            endsAt: Date(timeIntervalSince1970: 4000))])   // ended before now
        c.applyDecisionIfNeeded()
        XCTAssertTrue(c.loadSnapshots().isEmpty, "a lock whose endsAt has passed must lift")
    }

    func testStaysHeldBeforeEndsAt() throws {
        let now = FakeNow(Date(timeIntervalSince1970: 5000))
        let (c, url, cfg) = try make("expire-future", now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        try LockSnapshotStore(path: url).save([snap(id: "rule", mode: .scheduled,
            endsAt: Date(timeIntervalSince1970: 9000))])   // ends in the future
        c.applyDecisionIfNeeded()
        XCTAssertFalse(c.loadSnapshots().isEmpty, "a lock whose endsAt is still ahead must NOT lift")
    }

    // sleep/timezone have no effect: endsAt is absolute UTC, so only the now() instant matters.
    func testExpiryIgnoresHowNowWasReached() throws {
        let now = FakeNow(Date(timeIntervalSince1970: 8999))
        let (c, url, cfg) = try make("expire-edge", now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        try LockSnapshotStore(path: url).save([snap(id: "rule", mode: .scheduled,
            endsAt: Date(timeIntervalSince1970: 9000))])
        c.applyDecisionIfNeeded()
        XCTAssertFalse(c.loadSnapshots().isEmpty, "1s before end: held")
        now.instant = Date(timeIntervalSince1970: 9001)    // jump now past end (e.g. woke from sleep)
        c.applyDecisionIfNeeded()
        XCTAssertTrue(c.loadSnapshots().isEmpty, "1s after end: lifts")
    }
}
