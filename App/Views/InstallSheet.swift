import SwiftUI
import ServiceManagement

struct InstallSheet: View {
    @ObservedObject var gate: InstallGate
    @ObservedObject private var installer: InstallerService
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(gate: InstallGate) {
        self.gate = gate
        self.installer = gate.installer
    }

    private var daemonReady: Bool { installer.daemonStatus == .enabled }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40)).foregroundStyle(Theme.ember)

            VStack(spacing: Theme.Spacing.s) {
                Text("Turn on LockIn")
                    .font(Theme.displayFont(22, .bold)).foregroundStyle(Theme.mist)
                Text("Approve each background helper once in System Settings. Website blocking is required; app blocking is optional.")
                    .font(.system(size: 13)).foregroundStyle(Theme.mistDim)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }

            VStack(spacing: Theme.Spacing.s) {
                permissionRow(
                    title: "Website blocking",
                    subtitle: "Blocks sites across every browser",
                    required: true,
                    status: installer.daemonStatus,
                    approve: { Task { await gate.approveDaemon() } })
                permissionRow(
                    title: "App blocking",
                    subtitle: "Quits blocked apps when they open",
                    required: false,
                    status: installer.agentStatus,
                    approve: { installer.registerAgent() })
            }
            .frame(maxWidth: 400)

            if let error = installer.lastError {
                Text(error)
                    .font(.system(size: 12)).foregroundStyle(Theme.ember)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }

            Button("Continue") { gate.resolveIfReady() }
                .buttonStyle(.borderedProminent).tint(Theme.ember)
                .disabled(!daemonReady)

            Button("Cancel") { gate.cancel() }
                .buttonStyle(.borderless)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .background(Theme.inkBase)
        .onAppear { installer.refreshStatus() }
        .onReceive(poll) { _ in
            installer.registerAgentIfDaemonReady()
            installer.refreshStatus()
        }
    }

    private func permissionRow(title: String, subtitle: String, required: Bool,
                               status: SMAppService.Status, approve: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mist)
                    Text(required ? "Required" : "Optional")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.mistDim)
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
            }
            Spacer()
            if status == .enabled {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Approve", action: approve).buttonStyle(.bordered).tint(Theme.ember)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.inkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
