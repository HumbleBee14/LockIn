import SwiftUI

struct QuickLockView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var statusModel: StatusViewModel

    @State private var selectedBlockSetId: String?
    @State private var durationMinutes: Int = 60
    @State private var starting = false

    private let durations: [(String, Int)] = [
        ("15 min", 15), ("30 min", 30), ("1 hour", 60), ("2 hours", 120),
        ("4 hours", 240), ("8 hours", 480),
    ]

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
                    Disclosures.cannotCancel.frame(maxWidth: 460)
                }
                Spacer()
            }
            .padding(Theme.Spacing.l)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("No block sets yet.").font(.system(size: 13)).foregroundStyle(Theme.mistDim)
            Text("Create one in the Block Sets tab, then start a quick lock.")
                .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
        }
        .card()
    }

    private var blockSetPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("What to block").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            ForEach(store.config.blockSets, id: \.id) { set in
                Button {
                    selectedBlockSetId = set.id
                } label: {
                    HStack {
                        Image(systemName: selectedBlockSetId == set.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedBlockSetId == set.id ? Theme.ember : Theme.mistDim)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(set.name).foregroundStyle(Theme.mist)
                            Text("\(set.mode == .allowlist ? "Allow only" : "Block") · \(set.domains.count) site\(set.domains.count == 1 ? "" : "s")")
                                .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.m)
                    .background(Theme.inkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 460)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("For how long").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            Picker("", selection: $durationMinutes) {
                ForEach(durations, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .frame(maxWidth: 460)
    }

    private var startButton: some View {
        Button {
            start()
        } label: {
            Text(starting ? "Starting…" : "Start Lock")
                .frame(maxWidth: 460)
                .padding(.vertical, Theme.Spacing.s)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.ember)
        .disabled(selectedBlockSetId == nil || starting)
    }

    private func start() {
        guard let id = selectedBlockSetId,
              let set = store.config.blockSets.first(where: { $0.id == id }),
              !set.domains.isEmpty else { return }
        starting = true
        Task {
            _ = await store.commit()
            _ = await statusModel.startQuickLock(blockSetId: id, minutes: durationMinutes)
            await statusModel.refresh()
            starting = false
        }
    }
}
