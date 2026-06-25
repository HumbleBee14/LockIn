import SwiftUI

// multi-select popover picker shared by Quick Lock and the rule editor; enforces one mode
struct BlockSetPicker: View {
    let blockSets: [BlockSet]
    @Binding var selectedIds: Set<String>

    @State private var picking = false

    private var selected: [BlockSet] {
        blockSets.filter { selectedIds.contains($0.id) }
    }
    private var lockedMode: BlockSetMode? { selected.first?.mode }
    private func isDisabled(_ set: BlockSet) -> Bool {
        guard let mode = lockedMode else { return false }
        return set.mode != mode && !selectedIds.contains(set.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button { if !blockSets.isEmpty { picking = true } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label).foregroundStyle(selected.isEmpty ? Theme.mistDim : Theme.mist)
                        if !selected.isEmpty {
                            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                }
                .padding(Theme.Spacing.m)
                .background(Theme.inkSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(blockSets.isEmpty)
            .popover(isPresented: $picking, arrowEdge: .bottom) { popover }
            if blockSets.isEmpty {
                Text("Create a block set in the Block Sets tab to get started.")
                    .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
            }
        }
    }

    private var label: String {
        if blockSets.isEmpty { return "No block sets yet" }
        if selected.isEmpty { return "Choose block sets" }
        if selected.count == 1 { return selected[0].name }
        return "\(selected[0].name) +\(selected.count - 1)"
    }

    private var detail: String {
        var seen = Set<String>()
        for set in selected { for d in set.domains { seen.insert(d) } }
        let n = seen.count
        let mode = lockedMode == .allowlist ? "Allowlist" : "Blocklist"
        return "\(mode) · \(n) site\(n == 1 ? "" : "s")"
    }

    static func subtitle(_ set: BlockSet) -> String {
        let mode = set.mode == .allowlist ? "Allowlist" : "Blocklist"
        var parts = ["\(set.domains.count) site\(set.domains.count == 1 ? "" : "s")"]
        if !set.appBundleIds.isEmpty {
            parts.append("\(set.appBundleIds.count) app\(set.appBundleIds.count == 1 ? "" : "s")")
        }
        return "\(mode) · \(parts.joined(separator: ", "))"
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose block sets")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                .padding(.horizontal, Theme.Spacing.m).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.xs)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(blockSets, id: \.id) { set in row(set) }
                }
            }
            .frame(maxHeight: blockSets.count > 4 ? 220 : nil)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .frame(width: 320)
    }

    private func row(_ set: BlockSet) -> some View {
        let on = selectedIds.contains(set.id)
        let disabled = isDisabled(set)
        return Button {
            if on { selectedIds.remove(set.id) } else { selectedIds.insert(set.id) }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Theme.ember : Theme.mistDim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(set.name).foregroundStyle(disabled ? Theme.mistDim : Theme.mist)
                    Text(Self.subtitle(set)).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                }
                Spacer()
            }
            .padding(.vertical, 8).padding(.horizontal, Theme.Spacing.m)
            .opacity(disabled ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(disabled ? "Can't mix allowlist and blocklist" : "")
    }
}
