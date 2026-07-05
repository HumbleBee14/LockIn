import SwiftUI

// the ONLY surface reachable while locked besides the lock screen itself: pick existing blocklist
// sets or create a brand-new one (create-only — existing sets stay untouchable during any lock)
struct StackLockSheet: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var statusModel: StatusViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<String> = []
    @State private var durationMinutes = 60
    @State private var customMode = false
    @State private var customMinutes: Double = 60
    @State private var starting = false
    @State private var failReason: String?
    @State private var showCreate = false
    @State private var newSetName = ""
    @State private var newSetDomains = ""

    private let presets: [(String, Int)] = [("30 min", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240)]
    private let maxMinutes = 22.0 * 60

    private var blocklistSets: [BlockSet] { store.config.blockSets.filter { $0.mode == .blocklist } }
    private var effectiveMinutes: Int { customMode ? Int(customMinutes.rounded()) : durationMinutes }
    private var canStart: Bool {
        !starting && !selectedIds.isEmpty
            && blocklistSets.contains { selectedIds.contains($0.id) && !$0.domains.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Add another lock")
                .font(Theme.displayFont(18, .semibold)).foregroundStyle(Theme.mist)
            Text("Stacks on top of what's already locked — it can only block more, and can't be turned off until it ends.")
                .font(.system(size: 12)).foregroundStyle(Theme.mistDim)

            if blocklistSets.isEmpty || showCreate {
                createForm
            }
            if !blocklistSets.isEmpty {
                BlockSetPicker(blockSets: blocklistSets, selectedIds: $selectedIds)
                if !showCreate {
                    Button("New block set…") { showCreate = true }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.ember)
                }
            }

            durationPicker
            startButton
        }
        .padding(Theme.Spacing.l)
        .frame(width: 460)
        .onAppear { showCreate = blocklistSets.isEmpty }
        .alert("Couldn’t start the lock", isPresented: Binding(
            get: { failReason != nil }, set: { if !$0 { failReason = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failReason ?? "") }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("New block set").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            TextField("Name", text: $newSetName).textFieldStyle(.roundedBorder)
            TextField("Sites (e.g. x.com, reddit.com)", text: $newSetDomains).textFieldStyle(.roundedBorder)
            Button("Create") {
                let domains = ScheduleStore.parseDomainList(newSetDomains)
                guard !newSetName.trimmingCharacters(in: .whitespaces).isEmpty, !domains.isEmpty else { return }
                let set = store.createBlockSet(title: newSetName, mode: .blocklist)
                store.addDomains(domains, toBlockSet: set.id)
                selectedIds.insert(set.id)
                newSetName = ""; newSetDomains = ""; showCreate = false
            }
            .tint(Theme.ember)
            .disabled(newSetName.trimmingCharacters(in: .whitespaces).isEmpty
                      || ScheduleStore.parseDomainList(newSetDomains).isEmpty)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("For how long").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(presets, id: \.1) { preset in
                    chip(preset.0, selected: !customMode && durationMinutes == preset.1) {
                        customMode = false; durationMinutes = preset.1
                    }
                }
                chip("Custom", selected: customMode) { customMode = true }
            }
            if customMode {
                Slider(value: $customMinutes, in: 1...maxMinutes).tint(Theme.ember)
            }
        }
    }

    private func chip(_ label: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(selected ? Theme.ember : Theme.inkRaised)
                .foregroundStyle(selected ? .white : Theme.mistDim)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var startButton: some View {
        Button {
            start()
        } label: {
            Text(starting ? "Starting…" : "Start Lock")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.m)
                .background(canStart ? Theme.ember : Theme.inkRaised)
                .foregroundStyle(canStart ? .white : Theme.mistDim)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
    }

    private func start() {
        let ids = Array(selectedIds)
        starting = true
        Task {
            _ = await store.commit()   // heal app→daemon config divergence before resolving (spec D5)
            let reason = await statusModel.startQuickLock(blockSetIds: ids, minutes: effectiveMinutes)
            await statusModel.refresh()
            starting = false
            if let reason { failReason = reason } else { dismiss() }
        }
    }
}
