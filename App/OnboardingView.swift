import SwiftUI
import ServiceManagement

struct OnboardingView: View {
    @StateObject private var installer = InstallerService()

    var body: some View {
        VStack(spacing: 16) {
            Text("Install LockIn's enforcement engine")
                .font(.headline)
            Text("Daemon: \(String(describing: installer.daemonStatus))")
            Text("Agent: \(String(describing: installer.agentStatus))")
            Button("Install") { try? installer.registerAll() }
            if installer.daemonStatus == .requiresApproval {
                Button("Approve in System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
        .padding(24)
        .onAppear { installer.refreshStatus() }
    }
}
