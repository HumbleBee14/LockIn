import XCTest
@testable import LockInDaemonCore

// spy: counts full apply() rebuilds and lets the test control whether the block "looks live"
private final class SpyBlocker: WebsiteBlocker, @unchecked Sendable {
    var applyCount = 0
    var present = false
    init() { super.init(forceVerified: true) }
    override func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        applyCount += 1
        present = true
        return true
    }
    // run engine ops synchronously in tests so counts are deterministic right after a tick
    override func applyAsync(domains: [String], allowlist: Bool, expandSubdomains: Bool) {
        _ = apply(domains: domains, allowlist: allowlist, expandSubdomains: expandSubdomains)
    }
    override func clearAsync() { clear() }
    override func liveBlockPresent() -> Bool { present }
    override func blockIntact(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool { present }
    override func clear() { present = false }
}

@MainActor
final class CheapReassertTests: XCTestCase {
    private func paths(_ n: String) -> (URL, URL) {
        let t = FileManager.default.temporaryDirectory
        return (t.appendingPathComponent("\(n)-active.plist"), t.appendingPathComponent("\(n)-cfg.plist"))
    }

    private func make(_ n: String) throws -> (BlockController, SpyBlocker, URL, URL) {
        let (url, cfg) = paths(n)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
        let store = ConfigStore(path: cfg)
        try store.save(ScheduleConfig(rules: []))
        let spy = SpyBlocker()
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url),
                                configStore: store, appBlocker: SpyAppBlocker(), blocker: spy)
        return (c, spy, url, cfg)
    }

    func testTickDoesNotRebuildWhenBlockStillLive() throws {
        let set = BlockSet(id: "a", name: "Ads", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        let (c, spy, url, cfg) = try make("cheap")
        try ConfigStore(path: cfg).save(ScheduleConfig(rules: [], blockSets: [set]))
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["a"], durationSeconds: 3600))
        let afterStart = spy.applyCount
        XCTAssertGreaterThan(afterStart, 0, "starting a lock must apply once")

        // several heartbeat ticks with the block intact must NOT rebuild
        for _ in 0..<5 { c.applyDecisionIfNeeded() }
        XCTAssertEqual(spy.applyCount, afterStart, "intact block must not be rebuilt every tick")

        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testTickRebuildsWhenBlockTampered() throws {
        let set = BlockSet(id: "a", name: "Ads", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        let (c, spy, url, cfg) = try make("tamper")
        try ConfigStore(path: cfg).save(ScheduleConfig(rules: [], blockSets: [set]))
        XCTAssertTrue(c.startQuickLock(blockSetIds: ["a"], durationSeconds: 3600))
        let afterStart = spy.applyCount

        spy.present = false  // simulate a tamper that removed the block from hosts/pf
        c.applyDecisionIfNeeded()
        XCTAssertEqual(spy.applyCount, afterStart + 1, "a removed block must be re-asserted within one tick")

        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }
}
