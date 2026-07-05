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
    var intact = true
    override func blockIntact(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }; return intact
    }
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

        // Force a TICK re-apply while BOTH locks are still live and disagree on expand:
        // the long lock ("s", expand=false) was persisted first, so snaps.first has expand=false.
        // Only the OR-based EffectiveBlock.effectiveExpand (not "use first snapshot's flag") can get
        // this right; blockIntact=false forces reconcile() to re-apply on the tick path (not the
        // stack path exercised above), so this pins the tick specifically.
        b.lock.lock(); b.intact = false; b.lock.unlock()
        c.reconcile()
        drainEngine(c)
        b.lock.lock(); b.intact = true; b.lock.unlock()
        let tickApply = b.lastApply()
        XCTAssertEqual(tickApply?.expand, true,
                        "tick re-apply must OR across both live snapshots, not just snaps.first's flag")
        XCTAssertEqual(tickApply?.domains, ["x.com", "adult.com"],
                        "tick re-apply's domain set is the two-lock union while both are live")

        now.d = now.d.addingTimeInterval(1200)   // expand=true snapshot expires
        c.reconcile(); drainEngine(c)
        XCTAssertEqual(b.lastApply()?.expand, false, "survivor never asked for expansion; OR drops to false")
    }

    // D7 regression: a successful append must NOT un-arm a pending retry. Scenario: a tick shrink
    // apply fails (engineDegraded=true, desiredEngine=.unknown), then a successful append happens.
    // appendAndWait only verifies the NEW entries, not the full union, so it must leave the retry
    // armed; only a full verified re-apply (the next tick) may clear engineDegraded.
    func testSuccessfulAppendDoesNotUnarmPendingRetry() throws {
        let social = BlockSet(id: "s", name: "Social", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        let adult = BlockSet(id: "a", name: "Adult", domains: ["adult.com"], appBundleIds: [], mode: .blocklist)
        let now = FakeNow(Date(timeIntervalSince1970: 1_700_000_000))
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("appendnounarm", sets: [social, adult], blocker: b, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["a"], durationSeconds: 7200))   // long, target
        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["s"], durationSeconds: 600))    // short
        now.d = now.d.addingTimeInterval(1200)   // past the short lock only
        b.lock.lock(); b.failNextApplies = 1; b.lock.unlock()
        c.reconcile()                            // shrink apply fails -> engineDegraded=true, desiredEngine=.unknown
        drainEngine(c)
        XCTAssertEqual(c.statusDTO().engineDegraded, true, "failed shrink must surface as degraded")

        // a successful append lands on the surviving (longest-ending) lock
        XCTAssertNil(c.appendDomainsToActiveBlockReason(["reddit.com"]))
        XCTAssertEqual(c.statusDTO().engineDegraded, true,
                       "append only verifies the new entries — it must not un-arm the pending D7 retry")

        // next tick must still see the retry armed and perform a full verified union re-apply
        c.reconcile()
        drainEngine(c)
        XCTAssertEqual(c.statusDTO().engineDegraded ?? true, false,
                       "the retried tick apply verifies the full union and clears the flag")
        XCTAssertEqual(lastApplyDomains(b), ["adult.com", "reddit.com"],
                       "the retry re-applies the full survivor union, including the appended domain")
    }

    // FIX 2a: rollback with existing locks — stacking B fails; A's exact union must be restored verified,
    // A's snapshot must be the only one left, and the flag must read clean (the restore succeeded).
    func testFailedStackApplyRestoresExistingLockUnion() throws {
        let social = BlockSet(id: "s", name: "Social", domains: ["x.com", "shared.com"], appBundleIds: [], mode: .blocklist)
        let adult = BlockSet(id: "a", name: "Adult", domains: ["adult.com"], appBundleIds: [], mode: .blocklist)
        let now = FakeNow(Date(timeIntervalSince1970: 1_700_000_000))
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("rollbackexisting", sets: [social, adult], blocker: b, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["s"], durationSeconds: 3600))   // A succeeds
        let aUnion: Set<String> = ["x.com", "shared.com"]
        XCTAssertEqual(lastApplyDomains(b), aUnion)

        b.lock.lock(); b.failNextApplies = 1; b.lock.unlock()   // only the forward (union) apply fails
        let reason = c.startQuickLockReason(blockSetIds: ["a"], durationSeconds: 600)
        XCTAssertNotNil(reason, "a failed stack apply must return a reason")

        XCTAssertEqual(c.loadSnapshots().count, 1, "B must never be saved; exactly A's snapshot remains")
        XCTAssertEqual(Set(c.loadSnapshots()[0].appliedDomains), aUnion)
        XCTAssertEqual(lastApplyDomains(b), aUnion, "the restore (last apply) re-applied A's exact union")
        XCTAssertEqual(c.statusDTO().engineDegraded ?? true, false, "the verified restore clears any degraded flag")
    }

    // FIX 2b: rollback where the restore ALSO fails — must surface degraded and stay recoverable by
    // a later successful reconcile, which re-applies A's union and clears the flag (D7 tick retry).
    func testFailedStackApplyAndFailedRestoreSurfacesDegradedThenRecovers() throws {
        let social = BlockSet(id: "s", name: "Social", domains: ["x.com", "shared.com"], appBundleIds: [], mode: .blocklist)
        let adult = BlockSet(id: "a", name: "Adult", domains: ["adult.com"], appBundleIds: [], mode: .blocklist)
        let now = FakeNow(Date(timeIntervalSince1970: 1_700_000_000))
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("rollbackfail", sets: [social, adult], blocker: b, now: now)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["s"], durationSeconds: 3600))   // A succeeds
        let aUnion: Set<String> = ["x.com", "shared.com"]

        b.lock.lock(); b.failNextApplies = 2; b.lock.unlock()   // forward apply AND the restore both fail
        let reason = c.startQuickLockReason(blockSetIds: ["a"], durationSeconds: 600)
        XCTAssertNotNil(reason, "a failed stack apply must return a reason")

        XCTAssertEqual(c.loadSnapshots().count, 1, "B must never be saved; exactly A's snapshot remains")
        XCTAssertEqual(c.statusDTO().engineDegraded, true, "a failed restore must surface as degraded")

        // recovery: a later successful reconcile + drain re-applies A's union and clears the flag
        c.reconcile()
        drainEngine(c)
        XCTAssertEqual(c.statusDTO().engineDegraded ?? true, false, "the retried tick apply converges and clears it")
        XCTAssertEqual(lastApplyDomains(b), aUnion, "convergence re-applies A's exact union")
    }

    // FIX 2c: stacking must refuse when the resulting UNION (not either set alone) would exceed the cap.
    func testStackUnionCapRefusedWithReason() throws {
        let bigDomains = (0..<(BlockLimits.maxActiveDomains - 1)).map { "d\($0).com" }
        let big = BlockSet(id: "big", name: "Big", domains: bigDomains, appBundleIds: [], mode: .blocklist)
        let extra = BlockSet(id: "extra", name: "Extra", domains: ["extra1.com", "extra2.com"],
                             appBundleIds: [], mode: .blocklist)
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("stackunioncap", sets: [big, extra], blocker: b, now: FakeNow(Date()))
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["big"], durationSeconds: 3600))
        XCTAssertEqual(c.loadSnapshots().count, 1)

        let reason = c.startQuickLockReason(blockSetIds: ["extra"], durationSeconds: 600)
        XCTAssertEqual(reason, "This would exceed the maximum of \(BlockLimits.maxActiveDomains) blocked sites.")
        XCTAssertEqual(c.loadSnapshots().count, 1, "a refused stack must not add a snapshot")
    }

    // FIX 2d: append must hit the UNION-cap guard specifically, not the per-target guard, when the
    // append target (latest-ending) is itself far under its own per-target cap. Construct: A is the
    // big, SHORT-lived lock (99,999 domains); B is the small, LONG-lived lock (1 domain) — B is the
    // append target. Stacking A+B lands the union exactly at the cap (100,000, allowed). Appending
    // one more fresh domain keeps B's own count trivially under cap but pushes the union over it.
    func testAppendUnionCapRefusedWhenTargetIsUnderPerTargetCap() throws {
        let bigDomains = (0..<(BlockLimits.maxActiveDomains - 1)).map { "d\($0).com" }
        let big = BlockSet(id: "big", name: "Big", domains: bigDomains, appBundleIds: [], mode: .blocklist)
        let small = BlockSet(id: "small", name: "Small", domains: ["small.com"], appBundleIds: [], mode: .blocklist)
        let b = FlakyBlocker(forceVerified: true)
        let (c, url, cfg) = try make("appendunioncap", sets: [big, small], blocker: b, now: FakeNow(Date()))
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["big"], durationSeconds: 600))     // short: A, target initially
        XCTAssertNil(c.startQuickLockReason(blockSetIds: ["small"], durationSeconds: 7200))  // long: B becomes target
        XCTAssertEqual(c.statusDTO().appendTargetBlockSetId, "small", "the small, longer-lived lock is the append target")
        XCTAssertEqual(Set(c.loadSnapshots().flatMap(\.appliedDomains)).count, BlockLimits.maxActiveDomains,
                       "union sits exactly at the cap before the append")

        let reason = c.appendDomainsToActiveBlockReason(["fresh-one-more.com"])
        XCTAssertEqual(reason, "This would exceed the maximum of \(BlockLimits.maxActiveDomains) blocked sites.",
                       "the union guard must trip even though the target's own domain count is trivially under cap")
    }
}
