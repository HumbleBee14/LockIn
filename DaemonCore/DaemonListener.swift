import Foundation
import Security

public final class DaemonListener: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener

    public override init() {
        listener = NSXPCListener(machServiceName: XPCRequirements.daemonServiceName)
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
        guard SecRequirementCreateWithString(XPCRequirements.daemonClientRequirement as CFString,
                                             [], &requirement) == errSecSuccess,
              let req = requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }

    public func listener(_ listener: NSXPCListener,
                         shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Anti-bypass invariant: identity comes from the kernel audit token, never the PID (CVE-2020-14977).
        guard isClientValid(newConnection.auditToken) else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: LockInDaemonProtocol.self)
        newConnection.exportedObject = DaemonXPC()
        newConnection.resume()
        return true
    }
}

final class DaemonXPC: NSObject, LockInDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void) {
        reply(LockInVersion.current)
    }
}
