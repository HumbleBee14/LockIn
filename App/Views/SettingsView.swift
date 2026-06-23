import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ScheduleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Settings")
                    .font(Theme.displayFont(24, .bold))
                    .foregroundStyle(Theme.mist)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Toggle(isOn: binding(\.clockTamperProtection)) {
                        settingLabel("Clock-tamper protection",
                                     "Holds blocks even if the system clock is moved forward. Recommended.")
                    }
                    Divider()
                    Toggle(isOn: binding(\.appBlockingEnabled)) {
                        settingLabel("App blocking",
                                     "Quit blocked apps when they launch during a window.")
                    }
                    Disclosures.appBlockingSoft
                    Divider()
                    Toggle(isOn: binding(\.blockSettingsPaneWhileActive)) {
                        settingLabel("Block the Date & Time pane while active",
                                     "Extra hardening against clock changes. Off by default.")
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.sage)
                .card()
                .frame(maxWidth: 520)
                Spacer()
            }
            .padding(Theme.Spacing.l)
        }
    }

    private func settingLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.mist)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                .fixedSize(horizontal: false, vertical: true)
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
