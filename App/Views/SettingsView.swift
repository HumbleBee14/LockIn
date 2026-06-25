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
                Spacer()
            }
            .padding(Theme.Spacing.l)
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
