import Foundation

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

    func status() async -> DaemonStatus? {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: nil) }
                as? LockInDaemonProtocol
            proxy?.getStatus { data in
                cont.resume(returning: data.flatMap { try? JSONDecoder().decode(DaemonStatus.self, from: $0) })
            }
        }
    }

    func startQuickLock(blockSetIds: [String], duration: TimeInterval) async -> Bool {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: false) }
                as? LockInDaemonProtocol
            proxy?.startQuickLock(blockSetIds: blockSetIds, durationSeconds: duration) { ok in
                cont.resume(returning: ok)
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
