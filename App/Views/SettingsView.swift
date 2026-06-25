import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ScheduleStore
    let client: DaemonClient

    @State private var resetting = false
    @State private var showResetConfirm = false
    @State private var resetResult: String?
    @State private var uninstalling = false
    @State private var showUninstallConfirm = false
    @State private var uninstallResult: String?
    private let installer = InstallerService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Settings")
                    .font(Theme.displayFont(24, .bold))
                    .foregroundStyle(Theme.mist)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    settingRow("Clock-tamper protection",
                               "Holds blocks even if the system clock is moved forward. Recommended.",
                               binding(\.clockTamperProtection))
                    Divider()
                    settingRow("App blocking",
                               "Quit blocked apps when they launch during a window.",
                               binding(\.appBlockingEnabled))
                    Divider()
                    settingRow("Expand www variants",
                               "Also block the www. version of each site. Off keeps lists smaller so larger blocklists stay responsive.",
                               binding(\.expandSubdomains))
                }
                .card()
                .frame(maxWidth: 520)

                recoveryCard
                Spacer()
            }
            .padding(Theme.Spacing.l)
        }
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Recovery").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mist)
            Text("If your hosts file ever looks wrong, reset it to the macOS default. Only available when no lock is active.")
                .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(resetting ? "Resetting…" : "Reset hosts to macOS default") { showResetConfirm = true }
                    .disabled(resetting)
                if let resetResult {
                    Text(resetResult).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                }
            }

            Divider().padding(.vertical, Theme.Spacing.xs)

            Text("Uninstall removes the background helpers, resets your hosts file, and clears all LockIn data. Then drag LockIn to the Trash. Only available when no lock is active.")
                .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(uninstalling ? "Uninstalling…" : "Uninstall LockIn") { showUninstallConfirm = true }
                    .disabled(uninstalling)
                    .tint(Theme.ember)
                if let uninstallResult {
                    Text(uninstallResult).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                }
            }
        }
        .card()
        .frame(maxWidth: 520)
        .confirmationDialog("Reset hosts file to the macOS default?",
                            isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This rewrites /etc/hosts to the system default. Any custom entries you added will be removed.")
        }
        .confirmationDialog("Uninstall LockIn?",
                            isPresented: $showUninstallConfirm, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the background helpers, resets your hosts file, and deletes all block sets and schedules. Then move LockIn to the Trash yourself.")
        }
    }

    private func reset() {
        resetting = true; resetResult = nil
        Task {
            let ok = await client.resetHostsToDefault()
            resetting = false
            resetResult = ok ? "Done." : "Couldn't reset (a lock may be active)."
        }
    }

    private func uninstall() {
        uninstalling = true; uninstallResult = nil
        Task {
            // daemon first: resets hosts + clears root data, refuses if a lock is active
            let ok = await client.prepareUninstall()
            guard ok else {
                uninstalling = false
                uninstallResult = "Couldn't uninstall (a lock may be active)."
                return
            }
            await installer.unregisterAll()
            ConfigPersistence.remove()
            store.config = ScheduleConfig(rules: [])
            uninstalling = false
            uninstallResult = "Done. Now drag LockIn to the Trash."
        }
    }

    private func settingRow(_ title: String, _ subtitle: String, _ value: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.mist)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.m)
            Toggle("", isOn: value)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.sage)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SettingsConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.config.settings[keyPath: keyPath] },
            set: {
                store.config.settings[keyPath: keyPath] = $0
                Task { _ = await store.commit() }
            })
    }
}
