import XCTest
@testable import LockInDaemonCore

@MainActor
final class LockLiftDeadlockTests: XCTestCase {
    private func paths(_ name: String) -> (URL, URL) {
        let t = FileManager.default.temporaryDirectory
        return (t.appendingPathComponent("\(name)-active.plist"),
                t.appendingPathComponent("\(name)-config.plist"))
    }

    private func makeController(_ name: String, wall: FakeWallClock, mono: FakeMonotonicClock,
                                boot: FakeBootSession, trusted: FakeTrustedTimeSource)
        throws -> (BlockController, WebsiteBlocker, URL, URL) {
        let (url, cfg) = paths(name)
        try? FileManager.default.removeItem(at: url)
        let cfgStore = ConfigStore(path: cfg)
        try cfgStore.save(ScheduleConfig(rules: []))
        let blocker = WebsiteBlocker(forceVerified: true)
        let c = BlockController(snapshotStore: LockSnapshotStore(path: url), configStore: cfgStore,
                                appBlocker: SpyAppBlocker(), blocker: blocker,
                                makeGuard: { ClockGuard(wall: wall, monotonic: mono, boot: boot, trusted: trusted) })
        return (c, blocker, url, cfg)
    }

    private func writeSnapshot(_ snap: LockSnapshot, to url: URL) throws {
        try LockSnapshotStore(path: url).save([snap])
    }

    private func adHocSnapshot(duration: Double, anchorWall: Date, served: Double,
                               suspicious: Bool, boot: String) -> LockSnapshot {
        LockSnapshot(id: "quick", mode: .adHoc, windowEnd: nil, duration: duration,
            isAllowlist: false, appliedDomains: ["youtube.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "Block",
            anchorWallTime: anchorWall, trustedNowAtLastHeartbeat: anchorWall,
            servedElapsedAtLastHeartbeat: served, clockSuspicious: suspicious, bootSessionUUID: boot)
    }

    func testAdHocLockLiftsWhenServedDoneEvenIfSuspiciousAndOffline() throws {
        let start = Date(timeIntervalSince1970: 0)
        let wall = FakeWallClock(start.addingTimeInterval(99999))   // wall jumped far forward
        let mono = FakeMonotonicClock(120)                          // monotonic advanced 120s this boot
        let boot = FakeBootSession("B1")
        let trusted = FakeTrustedTimeSource(nil)                    // offline => no trusted time
        let (c, _, url, cfg) = try makeController("deadlock-adhoc",
            wall: wall, mono: mono, boot: boot, trusted: trusted)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        // 60s quick lock that has already served 60s (complete) and is flagged suspicious + offline
        try writeSnapshot(adHocSnapshot(duration: 60, anchorWall: start, served: 60,
                                        suspicious: true, boot: "B1"), to: url)

        c.applyDecisionIfNeeded(timeResolved: c.timeIsResolved())

        XCTAssertTrue(c.loadSnapshots().isEmpty, "a fully-served ad-hoc lock must lift even when suspicious+offline")
    }

    func testScheduledLockStaysHeldWhenSuspiciousAndOfflineBeforeWindowEnd() throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 5 * 3600)
        let wall = FakeWallClock(end.addingTimeInterval(3600))      // wall claims past window end
        let mono = FakeMonotonicClock(60)                           // only 60s actually elapsed
        let boot = FakeBootSession("B1")
        let trusted = FakeTrustedTimeSource(nil)
        let (c, _, url, cfg) = try makeController("deadlock-sched",
            wall: wall, mono: mono, boot: boot, trusted: trusted)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: cfg) }

        let snap = LockSnapshot(id: "rule", mode: .scheduled, windowEnd: end, duration: nil,
            isAllowlist: false, appliedDomains: ["youtube.com"], appliedAppBundleIds: [],
            appliedSettings: SettingsConfig(), blockSetId: "b", blockSetTitle: "Block",
            anchorWallTime: start, trustedNowAtLastHeartbeat: start, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: true, bootSessionUUID: "B1")
        try writeSnapshot(snap, to: url)

        c.applyDecisionIfNeeded(timeResolved: c.timeIsResolved())

        XCTAssertFalse(c.loadSnapshots().isEmpty, "a suspicious+offline scheduled lock must NOT lift early")
    }
}
