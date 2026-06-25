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
    @State private var uninstallDone = false
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
                    Divider()
                    notificationRow
                }
                .card()
                .frame(maxWidth: 520)

                recoveryCard
                developerFooter
                Spacer()
            }
            .padding(Theme.Spacing.l)
        }
    }

    private var notificationRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.mist)
                Text("Show a notification when a blocked app is quit. Enable LockIn in System Settings.")
                    .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.m)
            Button("Open") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered).tint(Theme.ember)
        }
    }

    private var developerFooter: some View {
        HStack {
            Link(destination: URL(string: "https://github.com/HumbleBee14/LockIn")!) {
                Label("GitHub (Open Source)", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11))
            }
            .tint(Theme.mistDim)
            Spacer()
            Text(AppVersion.display)
                .font(.system(size: 11))
                .foregroundStyle(Theme.mistDim)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 520)
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
            if uninstallDone {
                let canSelfDelete = SelfUninstaller.canSelfDelete()
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(canSelfDelete
                         ? "Cleanup complete. Remove the app to finish."
                         : "Uninstalled. Quit LockIn and drag it to the Trash.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.mist)
                }
                Button(canSelfDelete ? "Remove & Quit" : "Quit LockIn") {
                    if canSelfDelete { SelfUninstaller.selfDeleteAndQuit() } else { NSApp.terminate(nil) }
                }
                .tint(Theme.ember)
            } else {
                HStack {
                    Button(uninstalling ? "Uninstalling…" : "Uninstall LockIn") { showUninstallConfirm = true }
                        .disabled(uninstalling)
                        .tint(Theme.ember)
                    if let uninstallResult {
                        Text(uninstallResult).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                    }
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
            if !ok {
                switch await client.statusResult() {
                case .answered(let status) where status.active:
                    uninstalling = false
                    uninstallResult = "A lock is active — uninstall is blocked until it ends."
                    return
                case .answered:
                    uninstalling = false
                    uninstallResult = "Cleanup failed. Try “Reset hosts to macOS default” first."
                    return
                case .unreachable where installer.isReady():
                    // invariant: a registered-but-unreachable daemon may be holding a live lock — never tear down
                    uninstalling = false
                    uninstallResult = "Can’t reach the blocker right now. A lock may still be active — try again in a moment."
                    return
                case .unreachable:
                    break // no daemon registered (never installed / already gone): safe to clear app-side data
                }
            }
            installer.unregisterAll()
            ConfigPersistence.remove()
            store.config = ScheduleConfig(rules: [])
            uninstalling = false
            uninstallDone = true
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
