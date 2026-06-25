import SwiftUI
import AppKit

struct AppPickerSheet: View {
    let alreadyAdded: Set<String>
    let onAdd: ([String]) -> Void
    let onCancel: () -> Void

    @State private var apps: [AppInfo] = []
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Add apps to block")
                .font(Theme.displayFont(18, .bold)).foregroundStyle(Theme.mist)
            Text("Blocked apps are quit when they open while this set is active.")
                .font(.system(size: 12)).foregroundStyle(Theme.mistDim)

            HStack {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                TextField("Search apps", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.s).padding(.vertical, 6)
            .background(Theme.inkSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if loading {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(height: 200)
            } else {
                List {
                    ForEach(filtered) { app in
                        appRow(app)
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(height: 280)
            }

            HStack {
                Text("\(selected.count) selected").font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Add") { onAdd(Array(selected)) }
                    .buttonStyle(.borderedProminent).tint(Theme.ember)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 420)
        .task {
            apps = AppCatalog.installedAndRunning()
            loading = false
        }
    }

    private var filtered: [AppInfo] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func appRow(_ app: AppInfo) -> some View {
        let isAdded = alreadyAdded.contains(app.bundleId)
        let isOn = selected.contains(app.bundleId) || isAdded
        return Button {
            if isAdded { return }
            if selected.contains(app.bundleId) { selected.remove(app.bundleId) }
            else { selected.insert(app.bundleId) }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                if let icon = AppCatalog.icon(forBundleId: app.bundleId) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(Theme.mistDim)
                }
                Text(app.name).foregroundStyle(Theme.mist).lineLimit(1)
                Spacer()
                if isAdded {
                    Text("Added").font(.system(size: 10)).foregroundStyle(Theme.mistDim)
                } else if isOn {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ember)
                } else {
                    Image(systemName: "circle").foregroundStyle(Theme.mistDim)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
    }
}
