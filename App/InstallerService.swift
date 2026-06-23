import Foundation
import ServiceManagement

@MainActor
final class InstallerService: ObservableObject {
    @Published var daemonStatus: SMAppService.Status = .notRegistered
    @Published var agentStatus: SMAppService.Status = .notRegistered

    private let daemon = SMAppService.daemon(plistName: "lockind.plist")
    private let agent = SMAppService.agent(plistName: "lockin-agent.plist")

    func registerAll() throws {
        try daemon.register()
        try agent.register()
        refreshStatus()
    }

    func refreshStatus() {
        daemonStatus = daemon.status
        agentStatus = agent.status
    }
}
