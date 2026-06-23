import Foundation
import ServiceManagement

@MainActor
final class InstallerService: ObservableObject {
    @Published var daemonStatus: SMAppService.Status = .notRegistered
    @Published var agentStatus: SMAppService.Status = .notRegistered

    @Published var lastError: String?

    private let daemon = SMAppService.daemon(plistName: "lockind.plist")
    private let agent = SMAppService.agent(plistName: "lockin-agent.plist")

    private var previewBypass: Bool {
        ProcessInfo.processInfo.environment["LOCKIN_PREVIEW"] == "1"
    }

    // live check, re-queried at each lock-creating action so a later helper removal is caught
    func isReady() -> Bool {
        if previewBypass { return true }
        refreshStatus()
        return daemonStatus == .enabled
    }

    var isInstalled: Bool { daemonStatus == .enabled }
    var needsApproval: Bool { daemonStatus == .requiresApproval || agentStatus == .requiresApproval }

    func registerAll() {
        do {
            try daemon.register()
            try agent.register()
            lastError = nil
        } catch {
            lastError = humanError(error)
        }
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
        case .notFound: return "Not available (this build isn't signed)"
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
