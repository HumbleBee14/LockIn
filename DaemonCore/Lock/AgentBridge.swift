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
        (connection.remoteObjectProxy as? LockInAgentProtocol)?.updateSnapshot(data) { _ in }
        connection.invalidate()
    }
}
