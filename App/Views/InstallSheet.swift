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
                Text("Approve LockIn once in System Settings. This turns on both website and app blocking.")
                    .font(.system(size: 13)).foregroundStyle(Theme.mistDim)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }

            VStack(spacing: Theme.Spacing.s) {
                permissionRow(
                    title: "Background helper",
                    subtitle: "Blocks sites across every browser and quits blocked apps",
                    status: installer.daemonStatus,
                    approve: { Task { await gate.approveAll() } })
            }
            .frame(maxWidth: 400)

            if let error = installer.lastError {
                Text(error)
                    .font(.system(size: 12)).foregroundStyle(Theme.ember)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }

            Button(gate.resolving ? "Checking…" : "Continue") { gate.resolveIfReady() }
                .buttonStyle(.borderedProminent).tint(Theme.ember)
                .disabled(gate.resolving)

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
            // clear a stale registration error once the required helper is actually approved
            if installer.daemonStatus == .enabled {
                installer.lastError = nil
                NotifierPriming.primeOnce()
            }
        }
    }

    private func permissionRow(title: String, subtitle: String,
                               status: SMAppService.Status, approve: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mist)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                    .fixedSize(horizontal: false, vertical: true)
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
