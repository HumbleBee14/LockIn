import Foundation
import Security

public final class AgentListener: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let observer: LaunchObserver

    public init(observer: LaunchObserver) {
        self.observer = observer
        listener = NSXPCListener(machServiceName: XPCRequirements.agentServiceName)
        super.init()
        listener.delegate = self
    }

    public func start() {
        listener.resume()
    }

    public func isClientValid(_ token: audit_token_t) -> Bool {
        var tokenCopy = token
        let tokenData = Data(bytes: &tokenCopy, count: MemoryLayout<audit_token_t>.size)
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let code = guest else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(XPCRequirements.agentClientRequirement as CFString,
                                             [], &requirement) == errSecSuccess,
              let req = requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }

    public func listener(_ listener: NSXPCListener,
                         shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Anti-bypass invariant: only the LockIn-signed daemon may push snapshots (audit token, not PID).
        guard isClientValid(newConnection.auditToken) else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: LockInAgentProtocol.self)
        newConnection.exportedObject = AgentXPC(observer: observer)
        newConnection.resume()
        return true
    }
}

final class AgentXPC: NSObject, LockInAgentProtocol {
    private let observer: LaunchObserver
    init(observer: LaunchObserver) { self.observer = observer }

    func updateSnapshot(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let snapshot = try? JSONDecoder().decode(BlockedAppSnapshot.self, from: data) else {
            reply(false); return
        }
        observer.updateSnapshot(snapshot)
        reply(true)
    }
}
