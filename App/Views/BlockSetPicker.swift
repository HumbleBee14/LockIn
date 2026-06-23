import SwiftUI

struct BlockSetPicker: View {
    let blockSets: [BlockSet]
    @Binding var selectedId: String?

    @State private var picking = false

    private var selectedSet: BlockSet? {
        blockSets.first { $0.id == selectedId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button { if !blockSets.isEmpty { picking = true } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .foregroundStyle(selectedSet == nil ? Theme.mistDim : Theme.mist)
                        if let set = selectedSet {
                            Text(Self.subtitle(set))
                                .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
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
        return selectedSet?.name ?? "Choose a block set"
    }

    static func subtitle(_ set: BlockSet) -> String {
        "\(set.mode == .allowlist ? "Allowlist" : "Blocklist") · \(set.domains.count) site\(set.domains.count == 1 ? "" : "s")"
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a block set")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                .padding(.horizontal, Theme.Spacing.m).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.xs)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(blockSets, id: \.id) { set in
                        let on = selectedId == set.id
                        Button {
                            selectedId = set.id
                            picking = false
                        } label: {
                            HStack(spacing: Theme.Spacing.s) {
                                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(on ? Theme.ember : Theme.mistDim)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(set.name).foregroundStyle(Theme.mist)
                                    Text(Self.subtitle(set)).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8).padding(.horizontal, Theme.Spacing.m)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: blockSets.count > 4 ? 220 : nil)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .frame(width: 300)
    }
}
