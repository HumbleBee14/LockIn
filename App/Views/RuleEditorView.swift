import SwiftUI

struct RuleEditorView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var gate: InstallGate
    let existing: Rule?
    let onDone: () -> Void

    @State private var window: ScheduleWindow
    @State private var selectedIds: Set<String>

    init(store: ScheduleStore, gate: InstallGate, existing: Rule?, onDone: @escaping () -> Void) {
        self.store = store
        self.gate = gate
        self.existing = existing
        self.onDone = onDone
        if let r = existing {
            _window = State(initialValue: ScheduleWindow(rule: r))
            _selectedIds = State(initialValue: Set(r.blockSetIds))
        } else {
            _window = State(initialValue: ScheduleWindow.upcoming())
            _selectedIds = State(initialValue: [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text(existing == nil ? "New Rule" : "Edit Rule")
                .font(Theme.displayFont(20, .bold))

            ScheduleWindowPicker(window: $window)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Block sets").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                BlockSetPicker(blockSets: store.config.blockSets, selectedIds: $selectedIds)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ember)
                    .disabled(!window.isValid || selectedIds.isEmpty)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 440)
    }

    private func save() {
        let rule = window.rule(id: existing?.id ?? UUID().uuidString, blockSetIds: Array(selectedIds))
        // an identical rule already covers this window — adding another would only arm a duplicate snapshot
        if store.config.rules.contains(where: { $0.id != rule.id && $0.sameWindow(as: rule) }) {
            if existing != nil { store.removeRule(id: rule.id) }
        } else {
            if existing != nil { store.removeRule(id: rule.id) }
            store.addRule(rule)
        }
        onDone()
        // arming a schedule needs the engine installed; gate the commit that reaches the daemon
        gate.require { _ = await store.commit() }
    }
}
