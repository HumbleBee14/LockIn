import XCTest
@testable import LockInDaemonCore

// recovery reset must be unconditional (the escape hatch when state is wrong) and never block the caller —
// it overwrites /etc/hosts with the macOS default regardless of whether a snapshot/lock is present.
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

    func testResetSucceedsEvenWhenSnapshotPresent() throws {
        let spy = ResetSpyBlocker()
        let (c, url, cfg) = try make("reset-locked", blocker: spy)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }
        // a lock snapshot exists — reset must STILL proceed (the old code refused here)
        try LockSnapshotStore(path: url).save([LockSnapshot(id: "quick", mode: .adHoc,
            endsAt: Date(timeIntervalSince1970: 9_999_999_999), isAllowlist: false, appliedDomains: ["x.com"],
            appliedAppBundleIds: [], appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "B")])

        let exp = expectation(description: "reset replied")
        c.resetHostsToDefault { ok in XCTAssertTrue(ok); exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(spy.resetCount, 1, "reset must run the engine reset unconditionally")
        XCTAssertTrue(c.loadSnapshots().isEmpty, "reset clears the snapshot so the daemon stops re-applying")
    }
}
