import Foundation
import ServiceManagement

@MainActor
final class InstallerService: ObservableObject {
    @Published var daemonStatus: SMAppService.Status = .notRegistered
    @Published var agentStatus: SMAppService.Status = .notRegistered

    @Published var lastError: String?

    private let daemon = SMAppService.daemon(plistName: "lockind.plist")
    private let agent = SMAppService.agent(plistName: "lockin-agent.plist")

    // the daemon (website blocking) gates a lock; the agent (app blocking) is best-effort and never blocks it
    func isReady() -> Bool {
        refreshStatus()
        return daemonStatus == .enabled
    }

    func unregisterAll() {
        try? daemon.unregister()
        try? agent.unregister()
        refreshStatus()
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

    // required website-blocking helper; re-registers a stale enabled job that no longer answers
    func registerDaemon(alive: Bool) {
        refreshStatus()
        if daemonStatus == .enabled && !alive {
            try? daemon.unregister()
            refreshStatus()
        }
        if daemonStatus == .enabled { openLoginItems(); return }
        do { try daemon.register() } catch { lastError = humanError(error) }
        refreshStatus()
    }

    // optional app-blocking helper; needs the daemon approved first so its prompt doesn't collide
    func registerAgent() {
        refreshStatus()
        if agentStatus == .enabled { openLoginItems(); return }
        guard daemonStatus == .enabled else {
            lastError = "Approve website blocking first, then app blocking."
            return
        }
        do { try agent.register() } catch { lastError = humanError(error) }
        refreshStatus()
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
        if ns.domain == "SMAppServiceErrorDomain" && ns.code == 1 {
            return "macOS blocked registration. A previous install may be stuck — reset background items in System Settings → Login Items and try again."
        }
        return ns.localizedDescription
    }
}
