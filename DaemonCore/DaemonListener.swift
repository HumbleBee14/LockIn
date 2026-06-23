import Foundation
import Security

public final class DaemonListener: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let controller: BlockController?

    public init(controller: BlockController? = nil) {
        self.controller = controller
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
        newConnection.exportedObject = DaemonXPC(controller: controller)
        newConnection.resume()
        return true
    }
}

final class DaemonXPC: NSObject, LockInDaemonProtocol {
    private let controller: BlockController?
    init(controller: BlockController?) { self.controller = controller }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(LockInVersion.current)
    }

    func registerSchedule(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let controller, let config = try? PropertyListDecoder().decode(ScheduleConfig.self, from: data) else {
            reply(false); return
        }
        reply(controller.registerSchedule(config))
    }

    func getStatus(reply: @escaping (Data?) -> Void) {
        guard let state = controller?.currentStatus() else { reply(nil); return }
        reply(try? PropertyListEncoder().encode(state))
    }

    func startAdHocBlock(blockSetId: String, durationSeconds: Double, reply: @escaping (Bool) -> Void) {
        guard let controller else { reply(false); return }
        reply(controller.startAdHocBlock(blockSetId: blockSetId, durationSeconds: durationSeconds))
    }
}
