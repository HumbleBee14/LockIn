import XCTest
@testable import LockInDaemonCore

// engine apply/clear synchronously drain queues + dispatch_sync the pf queue. if reconcile runs them inline
// on the main timer thread (schedule path did), or stacks one detached blocking call per tick (the bug we hit),
// the timer/XPC wedge and the daemon goes unresponsive. these pin: the tick never blocks, and engine calls coalesce.
private final class CountingSlowBlocker: WebsiteBlocker, @unchecked Sendable {
    let lock = NSLock()
    private var _applies = 0, _clears = 0
    var applyDelay: TimeInterval = 0
    var clearDelay: TimeInterval = 0
    private var _present = false
    var applies: Int { lock.lock(); defer { lock.unlock() }; return _applies }
    var clears: Int { lock.lock(); defer { lock.unlock() }; return _clears }
    init() { super.init(forceVerified: true) }
    override func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        if applyDelay > 0 { Thread.sleep(forTimeInterval: applyDelay) }
        lock.lock(); _applies += 1; _present = true; lock.unlock(); return true
    }
    override func blockIntact(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool { true }
    override func liveBlockPresent() -> Bool { lock.lock(); defer { lock.unlock() }; return _present }
    override func clear() -> Bool {
        if clearDelay > 0 { Thread.sleep(forTimeInterval: clearDelay) }
        lock.lock(); _clears += 1; _present = false; lock.unlock(); return true
    }
}

private final class FixedNow: NowProvider {
    var d: Date; init(_ d: Date) { self.d = d }; func now() -> Date { d }
}

@MainActor
final class ClearDoesNotBlockTickTests: XCTestCase {
    private func make(_ n: String, blocker: WebsiteBlocker, now: FixedNow) throws -> (BlockController, URL, URL) {
        let t = FileManager.default.temporaryDirectory
        let url = t.appendingPathComponent("\(n)-active.plist")
        let cfg = t.appendingPathComponent("\(n)-cfg.plist")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
        let store = ConfigStore(path: cfg); try store.save(ScheduleConfig(rules: []))
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: store,
                                appBlocker: SpyAppBlocker(), blocker: blocker, nowProvider: now)
        return (c, url, cfg)
    }

    private func expiredSnap(_ url: URL) throws {
        try LockSnapshotStore(path: url).save([LockSnapshot(id: "quick", mode: .adHoc,
            endsAt: Date(timeIntervalSince1970: 1000), isAllowlist: false, appliedDomains: ["x.com"],
            appliedAppBundleIds: [], appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")])
    }

    private func elapsed(_ body: () -> Void) -> TimeInterval {
        let s = ProcessInfo.processInfo.systemUptime; body(); return ProcessInfo.processInfo.systemUptime - s
    }

    // the expiry tick must return fast even when teardown is slow, and the clear must still happen exactly once
    func testExpiryTickDoesNotBlockAndClearsOnce() throws {
        let blocker = CountingSlowBlocker(); blocker.clearDelay = 2.0
        let now = FixedNow(Date(timeIntervalSince1970: 5000))
        let (c, url, cfg) = try make("expire", blocker: blocker, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        // establish a live lock first (sets desired state + marks the engine "present"), THEN expire it
        let set = BlockSet(id: "ads", name: "Ads", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        try ConfigStore(path: cfg).save(ScheduleConfig(rules: [], blockSets: [set]))
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["ads"], durationSeconds: 60))
        XCTAssertEqual(blocker.applies, 1, "quick lock applies once")

        now.d = Date(timeIntervalSince1970: 5000 + 120)   // jump past the 60s lock
        XCTAssertLessThan(elapsed { c.applyDecisionIfNeeded() }, 0.5, "expiry tick must not block on slow teardown")
        XCTAssertTrue(c.loadSnapshots().isEmpty, "expired snapshot removed immediately")

        // wait for the off-thread clear to land
        let deadline = Date().addingTimeInterval(6.0)
        while blocker.clears < 1 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(blocker.clears, 1, "expiry must trigger exactly one clear")

        // subsequent empty ticks must NOT stack up more clears (the bug: one blocking clear per tick)
        for _ in 0..<5 { _ = elapsed { c.applyDecisionIfNeeded() } }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(blocker.clears, 1, "teardown must coalesce to a single clear, not one per tick")
    }

    // a schedule firing a huge set must not freeze the tick (the original symptom: quick lock fine, schedule hangs)
    func testScheduleActivationDoesNotBlockTick() throws {
        let blocker = CountingSlowBlocker(); blocker.applyDelay = 2.0
        let now = FixedNow(Date(timeIntervalSince1970: 1_700_000_000))
        let (c, url, cfg) = try make("sched", blocker: blocker, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        let set = BlockSet(id: "ads", name: "Ads", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        // an always-on rule (00:00–23:59 every day) so it is due right now
        let rule = Rule(id: "r1", weekdays: Array(1...7), startHour: 0, startMinute: 0,
                        endHour: 23, endMinute: 59, blockSetIds: ["ads"], appBundleIds: [])
        try ConfigStore(path: cfg).save(ScheduleConfig(rules: [rule], blockSets: [set]))
        XCTAssertLessThan(elapsed { c.applyDecisionIfNeeded() }, 0.5, "schedule activation must not block the tick")

        let exp = expectation(description: "apply ran")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { exp.fulfill() }
        wait(for: [exp], timeout: 5.0)
        XCTAssertGreaterThan(blocker.applies, 0, "the due schedule must still have applied the block off-thread")
        XCTAssertFalse(c.loadSnapshots().isEmpty, "the schedule snapshot must be recorded")
    }
}
