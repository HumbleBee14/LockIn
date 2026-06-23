import SwiftUI

struct QuickLockView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var statusModel: StatusViewModel
    @ObservedObject var gate: InstallGate

    @State private var selectedBlockSetId: String?
    @State private var durationMinutes: Int = 60
    @State private var customMode = false
    @State private var customMinutes: Double = 60
    @State private var starting = false
    @State private var picking = false

    private let presets: [(String, Int)] = [
        ("30 min", 30), ("1 hour", 60), ("2 hours", 120),
        ("4 hours", 240), ("8 hours", 480),
    ]

    private let maxMinutes = 23.0 * 60

    private var effectiveMinutes: Int {
        customMode ? Int(customMinutes.rounded()) : durationMinutes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Lock")
                        .font(Theme.displayFont(24, .bold)).foregroundStyle(Theme.mist)
                    Text("Block now for a set time. Once started, it can't be turned off until it ends.")
                        .font(.system(size: 13)).foregroundStyle(Theme.mistDim)
                }

                if store.config.blockSets.isEmpty {
                    emptyState
                } else {
                    blockSetPicker
                    durationPicker
                    startButton
                    Disclosures.cannotCancel
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("No block sets yet.").font(.system(size: 13)).foregroundStyle(Theme.mistDim)
            Text("Create one in the Block Sets tab, then start a quick lock.")
                .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
        }
        .card()
    }

    private var selectedSet: BlockSet? {
        store.config.blockSets.first { $0.id == selectedBlockSetId }
    }

    private var blockSetPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("What to block").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            Button { picking = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedSet?.name ?? "Choose a block set")
                            .foregroundStyle(selectedSet == nil ? Theme.mistDim : Theme.mist)
                        if let set = selectedSet {
                            Text(subtitle(set))
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
            .popover(isPresented: $picking, arrowEdge: .bottom) { pickerPopover }
        }
        .frame(maxWidth: .infinity)
    }

    private func subtitle(_ set: BlockSet) -> String {
        "\(set.mode == .allowlist ? "Allowlist" : "Blocklist") · \(set.domains.count) site\(set.domains.count == 1 ? "" : "s")"
    }

    private var pickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a block set")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                .padding(.horizontal, Theme.Spacing.m).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.xs)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.config.blockSets, id: \.id) { set in
                        let on = selectedBlockSetId == set.id
                        Button {
                            selectedBlockSetId = set.id
                            picking = false
                        } label: {
                            HStack(spacing: Theme.Spacing.s) {
                                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(on ? Theme.ember : Theme.mistDim)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(set.name).foregroundStyle(Theme.mist)
                                    Text(subtitle(set)).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
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
            .frame(maxHeight: store.config.blockSets.count > 4 ? 220 : nil)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .frame(width: 300)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("For how long").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(presets, id: \.1) { preset in
                    durationChip(preset.0, selected: !customMode && durationMinutes == preset.1) {
                        customMode = false; durationMinutes = preset.1
                    }
                }
                durationChip("Custom", selected: customMode) { customMode = true }
            }
            if customMode { customSlider }
        }
        .frame(maxWidth: .infinity)
    }

    private func durationChip(_ label: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Theme.ember : Theme.inkRaised)
                .foregroundStyle(selected ? .white : Theme.mistDim)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var customSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Duration").font(.system(size: 12)).foregroundStyle(Theme.mistDim)
                Spacer()
                Text(customLabel).font(Theme.monoFont(13, .semibold)).foregroundStyle(Theme.ember)
            }
            Slider(value: $customMinutes, in: 1...maxMinutes).tint(Theme.ember)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private var customLabel: String {
        let total = effectiveMinutes
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hour\(h == 1 ? "" : "s")" : "\(h)h \(m)m"
    }

    private var startButton: some View {
        Button {
            start()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold))
                Text(starting ? "Starting…" : "Start Lock")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
            .background(canStart ? Theme.ember : Theme.inkRaised)
            .foregroundStyle(canStart ? .white : Theme.mistDim)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .frame(maxWidth: .infinity)
    }

    private var canStart: Bool {
        selectedBlockSetId != nil && !starting
    }

    private func start() {
        guard let id = selectedBlockSetId,
              let set = store.config.blockSets.first(where: { $0.id == id }),
              !set.domains.isEmpty else { return }
        gate.require {
            starting = true
            _ = await store.commit()
            _ = await statusModel.startQuickLock(blockSetId: id, minutes: effectiveMinutes)
            await statusModel.refresh()
            starting = false
        }
    }
}
