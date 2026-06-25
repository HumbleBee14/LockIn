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
        // authorize by kernel audit token, never PID
        guard isClientValid(newConnection.auditToken) else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: LockInDaemonProtocol.self)
        newConnection.exportedObject = DaemonXPC(controller: controller)
        newConnection.resume()
        return true
    }
}

// NSXPC reply blocks are documented thread-safe to invoke from any queue; this box lets us carry one
// across the hop to the main actor under Swift 6 strict concurrency without a real data race.
private struct ReplyBox<T>: @unchecked Sendable {
    let reply: (T) -> Void
    func callAsFunction(_ value: T) { reply(value) }
}

final class DaemonXPC: NSObject, LockInDaemonProtocol {
    private let controller: BlockController?
    init(controller: BlockController?) { self.controller = controller }

    // invariant: all controller access runs on main, matching the timer loop, so lock-state RMW can't race
    private func onMain<T>(_ reply: @escaping (T) -> Void, _ nilValue: T,
                           _ body: @escaping @MainActor (BlockController) -> T) {
        let box = ReplyBox(reply: reply)
        guard let controller else { box(nilValue); return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { box(body(controller)) }
        }
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(LockInVersion.current)
    }

    func registerSchedule(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let config = try? JSONDecoder().decode(ScheduleConfig.self, from: data) else { reply(false); return }
        onMain(reply, false) { $0.registerSchedule(config) }
    }

    func getStatus(reply: @escaping (Data?) -> Void) {
        onMain(reply, nil) { try? JSONEncoder().encode($0.statusDTO()) }
    }

    func startQuickLock(blockSetIds: [String], durationSeconds: Double, reply: @escaping (String?) -> Void) {
        onMain(reply, "The blocker isn’t running.") {
            $0.startQuickLockReason(blockSetIds: blockSetIds, durationSeconds: durationSeconds)
        }
    }

    func appendDomainsToActiveBlock(_ domains: [String], reply: @escaping (Bool) -> Void) {
        onMain(reply, false) { $0.appendDomainsToActiveBlock(domains) }
    }

    func resetHostsToDefault(reply: @escaping (Bool) -> Void) {
        onMain(reply, false) { $0.resetHostsToDefault() }
    }

    func prepareUninstall(reply: @escaping (Bool) -> Void) {
        onMain(reply, false) { $0.prepareUninstall() }
    }
}
