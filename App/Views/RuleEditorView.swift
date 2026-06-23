import SwiftUI

struct RuleEditorView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var gate: InstallGate
    let existing: Rule?
    let onDone: () -> Void

    @State private var weekdays: Set<Int>
    @State private var start: Date
    @State private var end: Date
    @State private var blockSetId: String

    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    init(store: ScheduleStore, gate: InstallGate, existing: Rule?, onDone: @escaping () -> Void) {
        self.store = store
        self.gate = gate
        self.existing = existing
        self.onDone = onDone
        let cal = Calendar.current
        if let r = existing {
            _weekdays = State(initialValue: Set(r.weekdays))
            _start = State(initialValue: cal.date(bySettingHour: r.startHour, minute: r.startMinute, second: 0, of: Date()) ?? Date())
            _end = State(initialValue: cal.date(bySettingHour: r.endHour, minute: r.endMinute, second: 0, of: Date()) ?? Date())
            _blockSetId = State(initialValue: r.blockSetId)
        } else {
            _weekdays = State(initialValue: [1, 2, 3, 4, 5, 6, 7])
            _start = State(initialValue: cal.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date())
            _end = State(initialValue: cal.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date())
            _blockSetId = State(initialValue: store.config.blockSets.first?.id ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text(existing == nil ? "New Rule" : "Edit Rule")
                .font(Theme.displayFont(20, .bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Days").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(1...7, id: \.self) { day in
                        let on = weekdays.contains(day)
                        Button {
                            if on { weekdays.remove(day) } else { weekdays.insert(day) }
                        } label: {
                            Text(weekdayLabels[day - 1])
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(on ? Theme.ember : Theme.inkRaised)
                                .foregroundStyle(on ? .white : Theme.mistDim)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: Theme.Spacing.xl) {
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
            }
            .datePickerStyle(.field)

            if store.config.blockSets.isEmpty {
                Text("Create a block set first (Block Sets tab).")
                    .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
            } else {
                Picker("Block set", selection: $blockSetId) {
                    ForEach(store.config.blockSets, id: \.id) { set in
                        Text(set.name).tag(set.id)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ember)
                    .disabled(weekdays.isEmpty)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: 440)
    }

    private func save() {
        let cal = Calendar.current
        let sc = cal.dateComponents([.hour, .minute], from: start)
        let ec = cal.dateComponents([.hour, .minute], from: end)
        let rule = Rule(id: existing?.id ?? UUID().uuidString,
                        weekdays: weekdays.sorted(),
                        startHour: sc.hour ?? 22, startMinute: sc.minute ?? 0,
                        endHour: ec.hour ?? 7, endMinute: ec.minute ?? 0,
                        blockSetId: blockSetId, appBundleIds: [])
        if existing != nil { store.removeRule(id: rule.id) }
        store.addRule(rule)
        onDone()
        // arming a schedule needs the engine installed; gate the commit that reaches the daemon
        gate.require { _ = await store.commit() }
    }
}
