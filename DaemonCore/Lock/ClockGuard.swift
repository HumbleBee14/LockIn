import Foundation

final class ClockGuard {
    private let wall: WallClock
    private let monotonic: MonotonicClock
    private let boot: BootSession
    private let trusted: TrustedTimeSource
    private let tickSlack: Double = 5.0
    private let cumulativeDriftLimit: Double = 45.0

    // anti-bypass invariant: in-memory only; never persist (prior boot's counter is meaningless)
    private var anchorMonotonic: Double

    init(wall: WallClock, monotonic: MonotonicClock, boot: BootSession, trusted: TrustedTimeSource) {
        self.wall = wall; self.monotonic = monotonic; self.boot = boot; self.trusted = trusted
        self.anchorMonotonic = monotonic.seconds
    }

    func heartbeat(_ state: LockState) -> LockState {
        var s = state
        let now = monotonic.seconds
        let sameBoot = (boot.uuid == s.bootSessionUUID)
        let liveDelta = max(0, now - anchorMonotonic)
        let served = s.servedElapsedAtLastHeartbeat + liveDelta

        // clock-tamper protection off (user setting): lenient, not wide-open. Trust normal wall advance,
        // but still cap at the monotonic served floor so a forward jump can't instantly expire a lock.
        if !s.appliedSettings.clockTamperProtection {
            let servedFloor = s.anchorWallTime.addingTimeInterval(served + tickSlack)
            s.servedElapsedAtLastHeartbeat = served
            s.trustedNowAtLastHeartbeat = min(wall.now, servedFloor)
            s.bootSessionUUID = boot.uuid
            s.anchorWallTime = sameBoot ? s.anchorWallTime : wall.now
            anchorMonotonic = now
            return s
        }

        if sameBoot {
            let wallAdvance = wall.now.timeIntervalSince(s.trustedNowAtLastHeartbeat)
            let drift = wallAdvance - liveDelta
            s.cumulativeDriftSeconds += max(0, drift)
            // drift is already wall-over-monotonic; trip on a single jump past slack or accumulated drift
            if drift > tickSlack || s.cumulativeDriftSeconds > cumulativeDriftLimit {
                s.clockSuspicious = true
            }
        }

        let cappedTrustedNow = computeTrustedNow(s, sameBoot: sameBoot, liveDelta: liveDelta)

        // only a successful online reconciliation clears suspicion; never local, never UI
        if s.clockSuspicious, let onlineNow = trusted.fetch(),
           abs(onlineNow.timeIntervalSince(cappedTrustedNow)) <= tickSlack {
            s.clockSuspicious = false
            s.cumulativeDriftSeconds = 0
        }

        s.servedElapsedAtLastHeartbeat = served
        s.trustedNowAtLastHeartbeat = cappedTrustedNow
        s.bootSessionUUID = boot.uuid
        s.anchorWallTime = sameBoot ? s.anchorWallTime : wall.now
        anchorMonotonic = now
        return s
    }

    // per-snapshot overloads reuse the LockState math exactly so the two paths can't diverge
    func heartbeat(_ snap: LockSnapshot) -> LockSnapshot {
        var state = LockState(active: true, mode: snap.mode, windowEnd: snap.windowEnd, duration: snap.duration,
            anchorWallTime: snap.anchorWallTime, trustedNowAtLastHeartbeat: snap.trustedNowAtLastHeartbeat,
            servedElapsedAtLastHeartbeat: snap.servedElapsedAtLastHeartbeat, clockSuspicious: snap.clockSuspicious,
            bootSessionUUID: snap.bootSessionUUID, appliedDomains: snap.appliedDomains,
            appliedAppBundleIds: snap.appliedAppBundleIds, appliedSettings: snap.appliedSettings,
            isAllowlist: snap.isAllowlist, blockSetId: snap.blockSetId, blockSetTitle: snap.blockSetTitle,
            scheduleRuleId: snap.mode == .scheduled ? snap.id : nil)
        state.cumulativeDriftSeconds = snap.cumulativeDriftSeconds
        let beat = heartbeat(state)
        var out = snap
        out.windowEnd = beat.windowEnd
        out.anchorWallTime = beat.anchorWallTime
        out.trustedNowAtLastHeartbeat = beat.trustedNowAtLastHeartbeat
        out.servedElapsedAtLastHeartbeat = beat.servedElapsedAtLastHeartbeat
        out.clockSuspicious = beat.clockSuspicious
        out.cumulativeDriftSeconds = beat.cumulativeDriftSeconds
        out.bootSessionUUID = beat.bootSessionUUID
        return out
    }

    func isExpired(_ snap: LockSnapshot) -> Bool {
        switch snap.mode {
        case .adHoc:
            guard let d = snap.duration else { return true }
            return snap.servedElapsedAtLastHeartbeat >= d
        case .scheduled:
            guard let end = snap.windowEnd else { return true }
            return snap.trustedNowAtLastHeartbeat >= end
        }
    }

    func trustedNow(_ s: LockState) -> Date { s.trustedNowAtLastHeartbeat }

    func hasTrustedTime() -> Bool { trusted.fetch() != nil }

    func isExpired(_ s: LockState) -> Bool {
        switch s.mode {
        case .adHoc:
            guard let d = s.duration else { return true }
            return s.servedElapsedAtLastHeartbeat >= d
        case .scheduled:
            guard let end = s.windowEnd else { return true }
            return trustedNow(s) >= end
        }
    }

    private func computeTrustedNow(_ s: LockState, sameBoot: Bool, liveDelta: Double) -> Date {
        // anti-bypass invariant: the monotonic ceiling is the cap; online only tightens, never ends early
        let sameBootCeiling = s.trustedNowAtLastHeartbeat.addingTimeInterval(liveDelta + tickSlack)

        if s.clockSuspicious {
            return s.trustedNowAtLastHeartbeat.addingTimeInterval(liveDelta)
        }
        if let onlineNow = trusted.fetch() {
            // anti-bypass invariant: online is tightening-only — never above the cap, EVEN across boot.
            // Cross-boot the cap is the served floor (monotonic survives reboot; powered-off time doesn't),
            // so a forged-future online reading from an admin MITM can't launder the clock past the reboot.
            let crossBootCeiling = s.anchorWallTime.addingTimeInterval(s.servedElapsedAtLastHeartbeat + liveDelta + tickSlack)
            return min(onlineNow, sameBoot ? sameBootCeiling : crossBootCeiling)
        }
        if sameBoot {
            return min(wall.now, sameBootCeiling)
        }
        // clean offline cold boot trusts the wall clock; do not add a served-floor here
        return wall.now
    }
}
