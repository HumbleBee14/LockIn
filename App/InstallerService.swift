import Foundation
import ServiceManagement

@MainActor
final class InstallerService: ObservableObject {
    @Published var daemonStatus: SMAppService.Status = .notRegistered
    @Published var agentStatus: SMAppService.Status = .notRegistered

    @Published var lastError: String?

    private let daemon = SMAppService.daemon(plistName: "lockind.plist")
    private let agent = SMAppService.agent(plistName: "lockin-agent.plist")

    enum Requirement {
        case daemonInstalled
        case agentInstalled
    }

    // ordered list of everything that must be true before a lock can start; add to extend the gate
    private let requirements: [Requirement] = [.daemonInstalled, .agentInstalled]

    private func isMet(_ requirement: Requirement) -> Bool {
        switch requirement {
        case .daemonInstalled: return daemonStatus == .enabled
        case .agentInstalled: return agentStatus == .enabled
        }
    }

    // first requirement not yet satisfied, or nil when everything is ready; re-queried live each call
    func firstUnmet() -> Requirement? {
        refreshStatus()
        return requirements.first { !isMet($0) }
    }

    func isReady() -> Bool { firstUnmet() == nil }

    var isInstalled: Bool { daemonStatus == .enabled }
    var needsApproval: Bool { daemonStatus == .requiresApproval || agentStatus == .requiresApproval }

    func unregisterAll() {
        try? daemon.unregister()
        try? agent.unregister()
        refreshStatus()
    }

    // register the daemon first; the agent is registered only once the daemon is enabled, because
    // registering both in one tick collides with the daemon's approval prompt and leaves the agent .notFound.
    // daemonAlive: a live ping result — an "enabled" job that doesn't answer is stale and gets re-registered.
    func registerAll(daemonAlive: Bool = false) {
        refreshStatus()
        if daemonStatus == .enabled && !daemonAlive {
            try? daemon.unregister()
            try? agent.unregister()
            refreshStatus()
        }
        if daemonStatus != .enabled {
            do { try daemon.register() } catch { lastError = humanError(error); refreshStatus(); return }
        }
        registerAgentIfDaemonReady()
        refreshStatus()
        lastError = needsApproval ? "Approve LockIn in System Settings to finish installing." : nil
    }

    // the agent registers cleanly only after the daemon is approved; called repeatedly by the poll
    func registerAgentIfDaemonReady() {
        refreshStatus()
        guard daemonStatus == .enabled else { return }
        if agentStatus == .notRegistered || agentStatus == .notFound {
            try? agent.register()
            refreshStatus()
        }
    }

    func refreshStatus() {
        daemonStatus = daemon.status
        agentStatus = agent.status
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "Not installed"
        case .enabled: return "Active"
        case .requiresApproval: return "Waiting for approval"
        case .notFound: return "Registering…"
        @unknown default: return "Unknown"
        }
    }

    private func humanError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.code == 1 {
            return "This build isn't code-signed, so macOS won't install the background blocker. Build a signed copy to enable it."
        }
        return ns.localizedDescription
    }
}
