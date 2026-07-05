import XCTest
@testable import LockInDaemonCore

private final class FakeNow: NowProvider, @unchecked Sendable {
    var d: Date
    init(_ d: Date) { self.d = d }
    func now() -> Date { d }
}

// per-call failure control + desired-set recording
private final class FlakyBlocker: WebsiteBlocker, @unchecked Sendable {
    let lock = NSLock()
    var failNextApplies = 0
    var applies: [(domains: Set<String>, allowlist: Bool, expand: Bool)] = []
    override func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        applies.append((Set(domains), allowlist, expandSubdomains))
        if failNextApplies > 0 { failNextApplies -= 1; return false }
        return true
    }
    override func appendToActiveBlock(newDomains: [String], expandSubdomains: Bool) -> Bool { true }
    override func clear() -> Bool { true }
    override func liveBlockPresent() -> Bool { false }
    override func blockIntact(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool { true }
    func lastApply() -> (domains: Set<String>, allowlist: Bool, expand: Bool)? {
        lock.lock(); defer { lock.unlock() }; return applies.last
    }
}

@MainActor
final class StackedExpiryTests: XCTestCase {
    private func make(_ name: String, sets: [BlockSet], blocker: WebsiteBlocker, now: FakeNow)
        throws -> (BlockController, URL, URL) {
        let t = FileManager.default.temporaryDirectory
        let url = t.appendingPathComponent("\(name)-active.plist")
        let cfg = t.appendingPathComponent("\(name)-config.plist")
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        try cfgStore.save(ScheduleConfig(rules: [], blockSets: sets))
        return (BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: cfgStore,
                                appBlocker: SpyAppBlocker(), blocker: blocker, nowProvider: now), url, cfg)
    }

    private func drainEngine(_ c: BlockController) {
        // tick applies complete async on the engine queue + main hop; poll briefly (existing suite pattern)
        let until = Date().addingTimeInterval(2)
        while Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    private func lastApplyDomains(_ b: FlakyBlocker) -> Set<String> { b.lastApply()?.domains ?? [] }

    // T8: shorter stacked lock expires → survivor's exact union re-applied; shared stays, unique goes
    func testShorterLockExpiryReappliesSurvivorUnion() throws {
        let social = BlockSet(id: "s", name: "Social", domains: ["x.com", "shared.com"], appBundleIds: [], mode: .blocklist)
        let adult = BlockSet(id: "a", name: "Adult", domains: ["adult.com", "shared.com"], appBundleIds: [], mode: .blocklist)
        let now = FakeNow(Date(timeIntervalSince1970: 1_700_000_000))
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("survivor", sets: [social, adult], blocker: b, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["a"], durationSeconds: 7200))   // long
        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["s"], durationSeconds: 600))    // short
        now.d = now.d.addingTimeInterval(1200)   // past the short lock only
        c.reconcile()
        drainEngine(c)
        XCTAssertEqual(c.loadSnapshots().count, 1, "expired snapshot must drop")
        XCTAssertEqual(lastApplyDomains(b), ["adult.com", "shared.com"],
                       "survivor's exact union re-applied: unique short-lock domain gone, shared stays")
        XCTAssertEqual(Set(c.statusDTO().appliedDomains), ["adult.com", "shared.com"])
    }

    // T14: failed shrink apply → degraded surfaces, tick retries, success clears it
    func testFailedShrinkApplySurfacesAndRetries() throws {
        let social = BlockSet(id: "s", name: "Social", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        let adult = BlockSet(id: "a", name: "Adult", domains: ["adult.com"], appBundleIds: [], mode: .blocklist)
        let now = FakeNow(Date(timeIntervalSince1970: 1_700_000_000))
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("shrinkfail", sets: [social, adult], blocker: b, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["a"], durationSeconds: 7200))
        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["s"], durationSeconds: 600))
        now.d = now.d.addingTimeInterval(1200)
        b.lock.lock(); b.failNextApplies = 1; b.lock.unlock()
        c.reconcile()                       // shrink apply fails
        drainEngine(c)
        XCTAssertEqual(c.statusDTO().engineDegraded, true, "failed shrink must surface")
        c.reconcile()                       // retry succeeds (desiredEngine == .unknown forces re-apply)
        drainEngine(c)
        XCTAssertEqual(c.statusDTO().engineDegraded ?? false, false, "verified retry clears the flag")
        XCTAssertEqual(lastApplyDomains(b), ["adult.com"])
    }

    // T12 (engine half): heterogeneous expand flags — OR is used by tick and stack identically
    func testHeterogeneousExpandFlagsUseOR() throws {
        // start lock A with expand=false in config, then flip config and stack B with expand=true
        let social = BlockSet(id: "s", name: "Social", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        let adult = BlockSet(id: "a", name: "Adult", domains: ["adult.com"], appBundleIds: [], mode: .blocklist)
        let now = FakeNow(Date(timeIntervalSince1970: 1_700_000_000))
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("expandor", sets: [social, adult], blocker: b, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        var config = c.loadConfig(); config.settings.expandSubdomains = false
        _ = c.registerSchedule(config)
        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["s"], durationSeconds: 7200))
        config.settings.expandSubdomains = true
        _ = c.registerSchedule(config)
        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["a"], durationSeconds: 600))
        XCTAssertEqual(b.lastApply()?.expand, true, "any live snapshot wanting expansion turns it on (OR)")
        now.d = now.d.addingTimeInterval(1200)   // expand=true snapshot expires
        c.reconcile(); drainEngine(c)
        XCTAssertEqual(b.lastApply()?.expand, false, "survivor never asked for expansion; OR drops to false")
    }
}
