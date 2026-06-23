import Foundation

final class ClockGuard {
    private let wall: WallClock
    private let monotonic: MonotonicClock
    private let boot: BootSession
    private let trusted: TrustedTimeSource
    private let tickSlack: Double = 5.0
    private let cumulativeDriftLimit: Double = 45.0

    // in-memory anchor: monotonic reading at the last heartbeat (or launch). NEVER persisted —
    // the prior boot's mach_continuous_time counter is meaningless after a reboot.
    private var anchorMonotonic: Double

    init(wall: WallClock, monotonic: MonotonicClock, boot: BootSession, trusted: TrustedTimeSource) {
        self.wall = wall; self.monotonic = monotonic; self.boot = boot; self.trusted = trusted
        self.anchorMonotonic = monotonic.seconds
    }

    func heartbeat(_ state: LockState) -> LockState {
        var s = state
        let now = monotonic.seconds
        let sameBoot = (boot.uuid == s.bootSessionUUID)
        // anchorMonotonic is in-memory, set at THIS process/boot's init and re-set each heartbeat — so
        // (now - anchorMonotonic) is always a true intra-boot interval, valid even on the first heartbeat
        // of a new boot. The prior boot's counter is never read (it's gone). Resume from persisted served.
        let liveDelta = max(0, now - anchorMonotonic)
        let served = s.servedElapsedAtLastHeartbeat + liveDelta

        if sameBoot {
            let wallAdvance = wall.now.timeIntervalSince(s.trustedNowAtLastHeartbeat)
            let drift = wallAdvance - liveDelta
            s.cumulativeDriftSeconds += max(0, drift)
            // trip on EITHER a single big jump (per-tick) OR accumulated slow salami drift (cumulative)
            if drift > liveDelta + tickSlack || s.cumulativeDriftSeconds > cumulativeDriftLimit {
                s.clockSuspicious = true
            }
        }

        let cappedTrustedNow = computeTrustedNow(s, sameBoot: sameBoot, liveDelta: liveDelta)

        // clear-path: ONLY a successful pinned online reconciliation clears suspicion (never local, never UI).
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

    func trustedNow(_ s: LockState) -> Date { s.trustedNowAtLastHeartbeat }

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
        // The monotonic cap is the CEILING. Online time never returns raw above it — it can only
        // clear-suspicion or tighten within the cap (spec §5b: online is a secondary cross-check,
        // never to end a block earlier than the mode's authority allows).
        let sameBootCeiling = s.trustedNowAtLastHeartbeat.addingTimeInterval(liveDelta + tickSlack)

        // 1. Suspicious (persists across reboot): never trust wall or raw online. Advance only by
        //    monotonic served (~0 across a reboot), so a forged clock can't be laundered.
        if s.clockSuspicious {
            return s.trustedNowAtLastHeartbeat.addingTimeInterval(liveDelta)
        }

        // 2. Online + not suspicious: bounded so it can't leap past what monotonic served this session.
        if let onlineNow = trusted.fetch() {
            if sameBoot { return min(onlineNow, sameBootCeiling) }
            return onlineNow
        }

        // 3. Same boot, not suspicious, offline: advance-cap to monotonic served (+slack).
        //    mach_continuous_time counts during SLEEP, so a genuine sleep advances correctly here.
        if sameBoot {
            return min(wall.now, sameBootCeiling)
        }

        // 4. New boot, not suspicious, offline: monotonic did NOT count powered-off time. Per spec §5b,
        //    trust the system wall clock so an honest "block until 07:00" ends at ~07:00 after a full
        //    overnight power-off. Accepted residual: forward-jump + clean offline cold boot can end early.
        return wall.now
    }
}
