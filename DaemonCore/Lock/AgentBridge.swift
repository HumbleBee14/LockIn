import Foundation

protocol AgentBridging {
    func push(_ snapshot: BlockedAppSnapshot)
}

final class AgentBridge: AgentBridging {
    func push(_ snapshot: BlockedAppSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let connection = NSXPCConnection(machServiceName: XPCRequirements.agentServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: LockInAgentProtocol.self)
        connection.resume()
        // invariant: invalidate only after the reply lands, so a dropped "clear" push isn't lost mid-flight.
        // The 15s re-push is the backstop if the connection itself fails.
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            connection.invalidate()
        } as? LockInAgentProtocol
        proxy?.updateSnapshot(data) { _ in connection.invalidate() }
    }
}
