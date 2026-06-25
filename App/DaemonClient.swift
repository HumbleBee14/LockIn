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
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: false) }
                as? LockInDaemonProtocol
            proxy?.getVersion { version in cont.resume(returning: version == LockInVersion.current) }
        }
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

    func appendDomains(_ domains: [String]) async -> Bool {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: false) }
                as? LockInDaemonProtocol
            proxy?.appendDomainsToActiveBlock(domains) { ok in cont.resume(returning: ok) }
        }
    }

    func resetHostsToDefault() async -> Bool {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: false) }
                as? LockInDaemonProtocol
            proxy?.resetHostsToDefault { ok in cont.resume(returning: ok) }
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
