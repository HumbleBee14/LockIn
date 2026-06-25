import XCTest
@testable import LockInDaemonCore

final class ClockGuardSnapshotTests: XCTestCase {
    private func makeGuard(wall: Date, mono: Double, boot: String, trusted: Date?)
        -> (ClockGuard, FakeWallClock, FakeMonotonicClock) {
        let w = FakeWallClock(wall); let m = FakeMonotonicClock(mono)
        return (ClockGuard(wall: w, monotonic: m, boot: FakeBootSession(boot),
                           trusted: FakeTrustedTimeSource(trusted)), w, m)
    }
    private func snap(windowEnd: Date, anchor: Date, boot: String) -> LockSnapshot {
        LockSnapshot(id: "r", mode: .scheduled, windowEnd: windowEnd, duration: nil, isAllowlist: false,
            appliedDomains: [], appliedAppBundleIds: [], appliedSettings: SettingsConfig(),
            blockSetId: "b", blockSetTitle: "B", anchorWallTime: anchor,
            trustedNowAtLastHeartbeat: anchor, servedElapsedAtLastHeartbeat: 0,
            clockSuspicious: false, cumulativeDriftSeconds: 0, bootSessionUUID: boot)
    }

    func testForwardJumpDoesNotExpireSnapshot() {
        let start = Date(timeIntervalSince1970: 0), end = Date(timeIntervalSince1970: 5 * 3600)
        var s = snap(windowEnd: end, anchor: start, boot: "B1")
        let (g, w, m) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m.seconds = 60; w.now = end.addingTimeInterval(1800)
        s = g.heartbeat(s)
        XCTAssertFalse(g.isExpired(s))
        XCTAssertTrue(s.clockSuspicious)
    }

    func testGenuineElapseExpiresSnapshot() {
        let start = Date(timeIntervalSince1970: 0), end = Date(timeIntervalSince1970: 5 * 3600)
        var s = snap(windowEnd: end, anchor: start, boot: "B1")
        let (g, w, m) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        m.seconds = 5 * 3600; w.now = end
        s = g.heartbeat(s)
        XCTAssertTrue(g.isExpired(s))
    }

    func testIndependentGuardsExpireOnlyTheirOwnSnapshot() {
        let start = Date(timeIntervalSince1970: 0)
        let shortEnd = Date(timeIntervalSince1970: 100), longEnd = Date(timeIntervalSince1970: 5 * 3600)
        var sShort = snap(windowEnd: shortEnd, anchor: start, boot: "B1")
        var sLong = snap(windowEnd: longEnd, anchor: start, boot: "B1")
        let (gS, wS, mS) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        let (gL, wL, mL) = makeGuard(wall: start, mono: 0, boot: "B1", trusted: nil)
        mS.seconds = 200; wS.now = Date(timeIntervalSince1970: 200)
        mL.seconds = 200; wL.now = Date(timeIntervalSince1970: 200)
        sShort = gS.heartbeat(sShort); sLong = gL.heartbeat(sLong)
        XCTAssertTrue(gS.isExpired(sShort), "the short window expired")
        XCTAssertFalse(gL.isExpired(sLong), "the long window is unaffected")
    }
}
