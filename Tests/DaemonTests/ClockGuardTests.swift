import XCTest
@testable import LockInDaemonCore

final class ClockGuardTests: XCTestCase {
    func testSystemBootSessionUUIDIsStableAndNonEmpty() {
        let b = SystemBootSession()
        let first = b.uuid
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, b.uuid, "boot session UUID must not change within a boot")
    }
    func testSystemMonotonicAdvances() {
        let m = SystemMonotonicClock()
        let a = m.seconds
        let b = m.seconds
        XCTAssertGreaterThanOrEqual(b, a)
    }

    private func makeGuard(wall: Date, mono: Double, boot: String, trusted: Date?)
        -> (ClockGuard, FakeWallClock, FakeMonotonicClock, FakeTrustedTimeSource) {
        let w = FakeWallClock(wall); let m = FakeMonotonicClock(mono)
        let b = FakeBootSession(boot); let t = FakeTrustedTimeSource(trusted)
        return (ClockGuard(wall: w, monotonic: m, boot: b, trusted: t), w, m, t)
    }
    private func scheduled(windowEnd: Date, anchorWall: Date, boot: String) -> LockState {
        LockState(active: true, mode: .scheduled, windowEnd: windowEnd, duration: nil,
            anchorWallTime: anchorWall, trustedNowAtLastHeartbeat: anchorWall,
            servedElapsedAtLastHeartbeat: 0, clockSuspicious: false,
            bootSessionUUID: boot, appliedDomains: [], appliedAppBundleIds: [])
    }
    private func adHoc(duration: Double, anchorWall: Date, boot: String) -> LockState {
        LockState(active: true, mode: .adHoc, windowEnd: nil, duration: duration,
            anchorWallTime: anchorWall, trustedNowAtLastHeartbeat: anchorWall,
            servedElapsedAtLastHeartbeat: 0, clockSuspicious: false,
            bootSessionUUID: boot, appliedDomains: [], appliedAppBundleIds: [])
    }

    func testScheduledBlockHoldsWhenClockJumpedPastWindowEnd() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 5 * 3600)
        var s = scheduled(windowEnd: end, anchorWall: start, boot: "B1")
        let (g, w, m, _) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m.seconds = 60
        w.now = end.addingTimeInterval(1800)
        s = g.heartbeat(s)
        XCTAssertFalse(g.isExpired(s), "forward jump must not expire a scheduled block")
        XCTAssertTrue(s.clockSuspicious, "divergence must be flagged")
    }

    func testScheduledBlockEndsAtWindowEndAfterOfflineSleep() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 5 * 3600)
        var s = scheduled(windowEnd: end, anchorWall: start, boot: "B1")
        let (g, w, m, _) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m.seconds = 5 * 3600
        w.now = end
        s = g.heartbeat(s)
        XCTAssertTrue(g.isExpired(s), "after a genuine 5h sleep the window has ended")
        XCTAssertFalse(s.clockSuspicious)
    }

    func testForwardJumpThenOfflineRebootDoesNotLaunderClock() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 5 * 3600)
        var s = scheduled(windowEnd: end, anchorWall: start, boot: "B1")
        let (g1, w1, m1, _) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m1.seconds = 30
        w1.now = end.addingTimeInterval(1800)
        s = g1.heartbeat(s)
        XCTAssertTrue(s.clockSuspicious)
        let (g2, _, _, _) = makeGuard(wall: end.addingTimeInterval(1800), mono: 5, boot: "B2", trusted: nil)
        s = g2.heartbeat(s)
        XCTAssertFalse(g2.isExpired(s), "offline reboot must not launder a forged forward clock")
    }

    func testAdHocBlockHoldsAfterForwardClockJump() {
        let start = Date(timeIntervalSince1970: 0)
        var s = adHoc(duration: 3600, anchorWall: start, boot: "B1")
        let (g, w, m, _) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m.seconds = 120
        w.now = start.addingTimeInterval(99999)
        s = g.heartbeat(s)
        XCTAssertFalse(g.isExpired(s), "ad-hoc expiry is served duration, not wall clock")
    }

    func testAdHocBlockLiftsByServedElapsedAcrossReboot() {
        let start = Date(timeIntervalSince1970: 0)
        var s = adHoc(duration: 3600, anchorWall: start, boot: "B1")
        let (g1, _, m1, _) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m1.seconds = 1800
        s = g1.heartbeat(s)
        XCTAssertFalse(g1.isExpired(s))
        XCTAssertEqual(s.servedElapsedAtLastHeartbeat, 1800, accuracy: 1)
        let (g2, _, m2, _) = makeGuard(wall: start.addingTimeInterval(3600), mono: 0, boot: "B2", trusted: nil)
        m2.seconds = 1800
        s = g2.heartbeat(s)
        XCTAssertTrue(g2.isExpired(s), "served 1800 (boot1) + 1800 (boot2) = 3600 across a reboot")
    }

    func testClockSuspicionClearsAfterOnlineReconciliation() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 5 * 3600)
        var s = scheduled(windowEnd: end, anchorWall: start, boot: "B1")
        let (g, w, m, t) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m.seconds = 30
        w.now = end.addingTimeInterval(1800)
        s = g.heartbeat(s)
        XCTAssertTrue(s.clockSuspicious)
        m.seconds = 60
        let consistentNow = s.trustedNowAtLastHeartbeat.addingTimeInterval(30)
        w.now = consistentNow
        t.value = consistentNow
        s = g.heartbeat(s)
        XCTAssertFalse(s.clockSuspicious, "pinned online reconciliation must clear suspicion")
    }

    func testForgedOnlineSourceCannotEndBlockEarly() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 5 * 3600)
        var s = scheduled(windowEnd: end, anchorWall: start, boot: "B1")
        let forgedFuture = end.addingTimeInterval(3600)
        let (g, _, m, _) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: forgedFuture)
        m.seconds = 60
        s = g.heartbeat(s)
        XCTAssertFalse(g.isExpired(s),
            "online time bounded by monotonic cap; a forged far-future reading cannot end the block")
    }

    func testSubSlackSalamiDriftTripsCumulativeSuspicion() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 5 * 3600)
        var s = scheduled(windowEnd: end, anchorWall: start, boot: "B1")
        let (g, w, m, _) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        var monoT = 0.0, wallT = 0.0
        for _ in 0..<12 {
            monoT += 15; wallT += 19
            m.seconds = monoT
            w.now = start.addingTimeInterval(wallT)
            s = g.heartbeat(s)
        }
        XCTAssertTrue(s.clockSuspicious,
            "accumulated sub-tickSlack drift (12×4s = 48s > cumulativeDriftLimit) must trip suspicion")
    }
}
