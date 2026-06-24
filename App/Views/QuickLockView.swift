import SwiftUI

struct QuickLockView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var statusModel: StatusViewModel
    @ObservedObject var gate: InstallGate
    @ObservedObject var draft: QuickLockDraft

    @State private var starting = false

    private let presets: [(String, Int)] = [
        ("30 min", 30), ("1 hour", 60), ("2 hours", 120),
        ("4 hours", 240), ("8 hours", 480),
    ]

    private let maxMinutes = 23.0 * 60

    private var effectiveMinutes: Int { draft.effectiveMinutes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Lock")
                        .font(Theme.displayFont(24, .bold)).foregroundStyle(Theme.mist)
                    Text("Block now for a set time. Once started, it can't be turned off until it ends.")
                        .font(.system(size: 13)).foregroundStyle(Theme.mistDim)
                }

                blockSetPicker
                durationPicker
                startButton
                Disclosures.cannotCancel
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }

    private var selectedSets: [BlockSet] {
        store.config.blockSets.filter { draft.selectedBlockSetIds.contains($0.id) }
    }

    private var lockedMode: BlockSetMode? { selectedSets.first?.mode }

    private var combinedDomainCount: Int {
        var seen = Set<String>()
        for set in selectedSets { for d in set.domains { seen.insert(d) } }
        return seen.count
    }

    private func isDisabled(_ set: BlockSet) -> Bool {
        guard let mode = lockedMode else { return false }
        return set.mode != mode && !draft.selectedBlockSetIds.contains(set.id)
    }

    private var blockSetPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("What to block").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            if store.config.blockSets.isEmpty {
                Text("Create a block set in the Block Sets tab to get started.")
                    .font(.system(size: 12)).foregroundStyle(Theme.mistDim).card()
            } else {
                ForEach(store.config.blockSets, id: \.id) { set in
                    blockSetRow(set)
                }
                if selectedSets.count > 1 {
                    Text("\(selectedSets.count) sets · \(combinedDomainCount) unique site\(combinedDomainCount == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                }
                if combinedDomainCount > BlockLimits.maxActiveDomains {
                    Label("Over \(BlockLimits.maxActiveDomains) sites — extra entries are skipped to keep macOS responsive.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.ember)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func blockSetRow(_ set: BlockSet) -> some View {
        let on = draft.selectedBlockSetIds.contains(set.id)
        let disabled = isDisabled(set)
        return Button {
            if on { draft.selectedBlockSetIds.remove(set.id) }
            else { draft.selectedBlockSetIds.insert(set.id) }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Theme.ember : Theme.mistDim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(set.name).foregroundStyle(disabled ? Theme.mistDim : Theme.mist)
                    Text(BlockSetPicker.subtitle(set)).font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                }
                Spacer()
            }
            .padding(Theme.Spacing.m)
            .background(Theme.inkSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(disabled ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(disabled ? "Can't mix allowlist and blocklist in one lock" : "")
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("For how long").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(presets, id: \.1) { preset in
                    durationChip(preset.0, selected: !draft.customMode && draft.durationMinutes == preset.1) {
                        draft.customMode = false; draft.durationMinutes = preset.1
                    }
                }
                durationChip("Custom", selected: draft.customMode) { draft.customMode = true }
            }
            if draft.customMode { customSlider }
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
            Slider(value: $draft.customMinutes, in: 1...maxMinutes).tint(Theme.ember)
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
        !selectedSets.isEmpty && combinedDomainCount > 0 && !starting
    }

    private func start() {
        let ids = selectedSets.map(\.id)
        guard !ids.isEmpty, combinedDomainCount > 0 else { return }
        gate.require {
            starting = true
            _ = await store.commit()
            _ = await statusModel.startQuickLock(blockSetIds: ids, minutes: effectiveMinutes)
            await statusModel.refresh()
            starting = false
        }
    }
}
