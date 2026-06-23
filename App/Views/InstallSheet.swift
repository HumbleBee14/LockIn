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

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40)).foregroundStyle(Theme.ember)

            VStack(spacing: Theme.Spacing.s) {
                Text("Turn on LockIn")
                    .font(Theme.displayFont(22, .bold)).foregroundStyle(Theme.mist)
                Text("LockIn needs to install a small background helper so it can block sites across every browser. You'll approve it once in System Settings.")
                    .font(.system(size: 13)).foregroundStyle(Theme.mistDim)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }

            HStack(spacing: Theme.Spacing.l) {
                statusPill("Blocker", InstallerService.describe(installer.daemonStatus))
                statusPill("Helper", InstallerService.describe(installer.agentStatus))
            }

            if installer.needsApproval {
                Button("Approve in System Settings") { installer.openLoginItems() }
                    .buttonStyle(.borderedProminent).tint(Theme.ember)
            } else {
                Button("Install") { installer.registerAll() }
                    .buttonStyle(.borderedProminent).tint(Theme.ember)
            }

            if let error = installer.lastError {
                Text(error)
                    .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }

            Button("Cancel") { gate.cancel() }
                .buttonStyle(.borderless)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .background(Theme.inkBase)
        .onAppear { installer.refreshStatus() }
        .onReceive(poll) { _ in gate.resolveIfReady() }
    }

    private func statusPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.mistDim)
            Text(value).font(.system(size: 12)).foregroundStyle(Theme.mist)
        }
        .padding(.vertical, Theme.Spacing.s).padding(.horizontal, Theme.Spacing.m)
        .background(Theme.inkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
