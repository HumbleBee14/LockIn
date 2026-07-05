import XCTest
@testable import LockInDaemonCore

// recovery reset is the escape hatch when hosts state is wrong and no lock is holding it. It is unconditional
// with respect to *dirty hosts* (empty/expired snapshot store + a lingering live block) but is refused while
// any un-expired snapshot exists — that's a live lock, and reset must never be a disguised unlock (D6).
private final class ResetSpyBlocker: WebsiteBlocker, @unchecked Sendable {
    var resetCount = 0
    init() { super.init(forceVerified: true) }
    override func resetToSystemDefaultAsync(completion: @escaping @Sendable (Bool) -> Void) {
        resetCount += 1; completion(true)
    }
}

@MainActor
final class ResetHostsTests: XCTestCase {
    private func make(_ n: String, blocker: WebsiteBlocker) throws -> (BlockController, URL, URL) {
        let t = FileManager.default.temporaryDirectory
        let url = t.appendingPathComponent("\(n)-active.plist")
        let cfg = t.appendingPathComponent("\(n)-cfg.plist")
        try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg)
        let store = ConfigStore(path: cfg); try store.save(ScheduleConfig(rules: []))
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: store,
                                appBlocker: SpyAppBlocker(), blocker: blocker)
        return (c, url, cfg)
    }

    func testResetRefusedWhileUnexpiredSnapshotPresent() throws {
        let spy = ResetSpyBlocker()
        let (c, url, cfg) = try make("reset-locked", blocker: spy)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        // an un-expired lock snapshot exists — reset must refuse (D6: reset is recovery, not an unlock)
        try LockSnapshotStore(path: url).save([LockSnapshot(id: "quick", mode: .adHoc,
            endsAt: Date(timeIntervalSince1970: 9_999_999_999), isAllowlist: false, appliedDomains: ["x.com"],
            appliedAppBundleIds: [], appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")])

        let exp = expectation(description: "reset replied")
        c.resetHostsToDefault { ok in XCTAssertFalse(ok); exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(spy.resetCount, 0, "a refused reset must never touch the engine")
        XCTAssertEqual(c.loadSnapshots().count, 1, "a refused reset must not clear the snapshot")
    }

    func testResetSucceedsWhenSnapshotStoreIsEmpty() throws {
        let spy = ResetSpyBlocker()
        let (c, url, cfg) = try make("reset-empty", blocker: spy)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        // no snapshot at all (e.g. dirty hosts lingering after a failed teardown) — this is the recovery path
        let exp = expectation(description: "reset replied")
        c.resetHostsToDefault { ok in XCTAssertTrue(ok); exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(spy.resetCount, 1, "reset must run the engine reset when no lock is holding hosts")
    }

    func testResetSucceedsWhenAllSnapshotsExpired() throws {
        let spy = ResetSpyBlocker()
        let (c, url, cfg) = try make("reset-expired", blocker: spy)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        // a stale, already-expired snapshot lingering on disk must not block recovery
        try LockSnapshotStore(path: url).save([LockSnapshot(id: "quick", mode: .adHoc,
            endsAt: Date(timeIntervalSince1970: 1), isAllowlist: false, appliedDomains: ["x.com"],
            appliedAppBundleIds: [], appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")])

        let exp = expectation(description: "reset replied")
        c.resetHostsToDefault { ok in XCTAssertTrue(ok); exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(spy.resetCount, 1, "an expired-only snapshot store must not block recovery")
    }
}
