import Foundation

// tri-state so callers can distinguish "daemon said no lock" from "couldn't reach the daemon".
// invariant: an unreachable daemon must NEVER read as "unlocked" for any destructive decision.
enum DaemonReachability {
    case answered(DaemonStatus)
    case unreachable
}

final class DaemonClient: Sendable {
    private func connection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: XPCRequirements.daemonServiceName)
        c.remoteObjectInterface = NSXPCInterface(with: LockInDaemonProtocol.self)
        c.resume()
        return c
    }

    func registerSchedule(_ config: ScheduleConfig) async -> Bool {
        guard let data = try? JSONEncoder().encode(config) else { return false }
        return await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: false) }
                as? LockInDaemonProtocol
            proxy?.registerSchedule(data) { ok in cont.resume(returning: ok) }
        }
    }

    // true only if the daemon answers AND runs our exact version — a stale/mismatched daemon fails here
    func ping() async -> Bool {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { err in
                LockInLog.error("daemon ping connection failed (service unreachable)", err)
                cont.resume(returning: false)
            } as? LockInDaemonProtocol
            proxy?.getVersion { version in
                if version != LockInVersion.current {
                    LockInLog.error("daemon ping: version mismatch app=\(LockInVersion.current) daemon=\(version)")
                }
                cont.resume(returning: version == LockInVersion.current)
            }
        }
    }

    enum Liveness { case current, older, unreachable }

    // tells "running but older" apart from "not answering" — ping() alone reads both as dead
    func liveness() async -> Liveness {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: .unreachable) }
                as? LockInDaemonProtocol
            proxy?.getVersion { version in cont.resume(returning: version == LockInVersion.current ? .current : .older) }
        }
    }

    // invariant: the blocker may only be removed once no lock is held — confirmed by the blocker itself,
    // or, when it can't answer, by no block left in /etc/hosts or /etc/pf.conf (both world-readable)
    func mayRemoveDaemon() async -> Bool {
        switch await liveness() {
        case .current: return false
        case .older: return await status()?.active == false
        case .unreachable: return !Self.liveBlockOnDisk()
        }
    }

    // the alive flag every register/unregister decision uses: false is the only path to removal
    func aliveForRegistration() async -> Bool { !(await mayRemoveDaemon()) }

    // mirrors the daemon's liveBlockPresent, read-only from the app side
    static func liveBlockOnDisk() -> Bool {
        if let pf = try? String(contentsOfFile: "/etc/pf.conf", encoding: .utf8),
           pf.contains("anchor \"com.humblebee.lockin\"") { return true }
        guard let hosts = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8),
              let h = hosts.range(of: "# BEGIN SELFCONTROL BLOCK"),
              let f = hosts.range(of: "# END SELFCONTROL BLOCK", range: h.upperBound..<hosts.endIndex) else { return false }
        return hosts[h.upperBound..<f.lowerBound].contains("0.0.0.0")
    }

    func status() async -> DaemonStatus? {
        if case .answered(let s) = await statusResult() { return s }
        return nil
    }

    // distinguishes a reachable daemon's answer from an unreachable daemon; a decode failure is unreachable
    func statusResult() async -> DaemonReachability {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: .unreachable) }
                as? LockInDaemonProtocol
            proxy?.getStatus { data in
                if let data, let s = try? JSONDecoder().decode(DaemonStatus.self, from: data) {
                    cont.resume(returning: .answered(s))
                } else {
                    cont.resume(returning: .unreachable)
                }
            }
        }
    }

    // nil on success; otherwise a short failure reason to show the user
    func startQuickLock(blockSetIds: [String], duration: TimeInterval) async -> String? {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in
                cont.resume(returning: "Couldn’t reach the blocker. Try again or reinstall the helper.")
            } as? LockInDaemonProtocol
            proxy?.startQuickLock(blockSetIds: blockSetIds, durationSeconds: duration) { reason in
                cont.resume(returning: reason)
            }
        }
    }

    // nil on success; otherwise a short failure reason to show the user
    func appendDomainsReason(_ domains: [String]) async -> String? {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in
                cont.resume(returning: "Couldn't reach the blocker. Try again or reinstall the helper.")
            } as? LockInDaemonProtocol
            proxy?.appendDomainsReturningReason(domains) { reason in cont.resume(returning: reason) }
        }
    }

    // blocks into the lock holding that set; endsAt = when that lock ends. a daemon from before this call
    // drops the connection, so fall back to the old call (longest-lived lock, end unknown) rather than fail
    func appendDomainsReason(_ domains: [String], toBlockSet id: String) async -> (reason: String?, endsAt: Date?) {
        if await liveness() == .older { return (await appendDomainsReason(domains), nil) }
        let answer: (String?, Date?)? = await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: nil) }
                as? LockInDaemonProtocol
            proxy?.appendDomains(domains, toBlockSetId: id) { reason, endsAt in cont.resume(returning: (reason, endsAt)) }
        }
        if let answer { return answer }
        return (await appendDomainsReason(domains), nil)
    }

    enum ResetResult { case done, failed, noHelper }

    func resetHostsToDefault() async -> ResetResult {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: .noHelper) }
                as? LockInDaemonProtocol
            proxy?.resetHostsToDefault { ok in cont.resume(returning: ok ? .done : .failed) }
        }
    }

    func prepareUninstall() async -> Bool {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: false) }
                as? LockInDaemonProtocol
            proxy?.prepareUninstall { ok in cont.resume(returning: ok) }
        }
    }
}
