import Foundation

final class DaemonClient {
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

    func startAdHoc(blockSetId: String, duration: TimeInterval) async -> Bool {
        await withCheckedContinuation { cont in
            let c = connection()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: false) }
                as? LockInDaemonProtocol
            proxy?.startAdHocBlock(blockSetId: blockSetId, durationSeconds: duration) { ok in
                cont.resume(returning: ok)
            }
        }
    }
}
