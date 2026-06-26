import XCTest
@testable import LockInDaemonCore

@MainActor
final class OrphanSelfDestructTests: XCTestCase {
    // isolated blocker: liveBlockPresent reflects only THIS test's state, never the real /etc/hosts
    private final class IsolatedBlocker: WebsiteBlocker {
        var present = false
        init() { super.init(forceVerified: true) }
        override func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool { present = true; return true }
        override func liveBlockPresent() -> Bool { present }
        override func clear() -> Bool { present = false; return true }
    }

    private func make(_ n: String, locked: Bool) throws -> (BlockController, URL, URL) {
        let t = FileManager.default.temporaryDirectory
        let url = t.appendingPathComponent("\(n)-active.plist")
        let cfg = t.appendingPathComponent("\(n)-cfg.plist")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cfg)
        let store = ConfigStore(path: cfg)
        let set = BlockSet(id: "a", name: "Ads", domains: ["x.com"], appBundleIds: [], mode: .blocklist)
        try store.save(ScheduleConfig(rules: [], blockSets: [set]))
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: store,
                                appBlocker: SpyAppBlocker(), blocker: IsolatedBlocker())
        if locked { _ = c.startQuickLock(blockSetIds: ["a"], durationSeconds: 3600) }
        return (c, url, cfg)
    }

    func testOrphanedWhenBundleMissingAndUnlocked() throws {
        let (c, url, cfg) = try make("orphan", locked: false)
        XCTAssertTrue(c.isOrphaned(appBundlePath: "/no/such/LockIn.app"))
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testNotOrphanedWhenBundleExists() throws {
        let (c, url, cfg) = try make("present", locked: false)
        XCTAssertFalse(c.isOrphaned(appBundlePath: "/Applications"))  // an existing dir stands in for the bundle
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }

    func testNeverOrphanedWhileLocked() throws {
        let (c, url, cfg) = try make("locked", locked: true)
        XCTAssertFalse(c.isOrphaned(appBundlePath: "/no/such/LockIn.app"),
                       "a held lock must keep the daemon alive even if the bundle is gone")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
    }
}
