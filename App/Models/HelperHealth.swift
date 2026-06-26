import Foundation
import ServiceManagement

enum ProtectionState {
    case allActive
    case degraded
    case notInstalled
}

struct ProtectionStatus {
    var websiteActive: Bool
    var appActive: Bool
    var installed: Bool

    var state: ProtectionState {
        if !installed { return .notInstalled }
        return (websiteActive && appActive) ? .allActive : .degraded
    }
}

@MainActor
final class HelperHealth: ObservableObject {
    @Published private(set) var status = ProtectionStatus(websiteActive: false, appActive: false, installed: false)
    @Published private(set) var reactivating = false

    private let installer: InstallerService
    private let client: DaemonClient

    init(installer: InstallerService = InstallerService(), client: DaemonClient = DaemonClient()) {
        self.installer = installer
        self.client = client
    }

    func refresh() async {
        installer.refreshStatus()
        let installed = installer.daemonStatus == .enabled
        let daemonAlive = installed ? await client.ping() : false
        let website = installed && daemonAlive
        let app = installer.agentStatus == .enabled && ProcessLiveness.isRunning(executableSuffix: "lockin-agent")
        status = ProtectionStatus(websiteActive: website, appActive: app, installed: installed)
    }

    func reactivate() async {
        reactivating = true
        defer { reactivating = false }
        let daemonAlive = await client.ping()
        if installer.daemonStatus == .enabled, !daemonAlive {
            installer.registerDaemon(alive: false)
        }
        installer.registerAgentIfDaemonReady()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await refresh()
    }
}
