import SwiftUI

struct ScheduleGridView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var statusModel: StatusViewModel
    @ObservedObject var gate: InstallGate
    @State private var editingRule: Rule?
    @State private var showingEditor = false

    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header
            if statusModel.isActive {
                DisclosureCallout(icon: "info.circle.fill", tint: Theme.sage,
                    title: "A block is active",
                    message: "Schedule changes apply to future windows only — they can't shorten or cancel the block running now.")
            }
            grid
            ruleList
            Spacer()
        }
        .padding(Theme.Spacing.l)
        .sheet(isPresented: $showingEditor) {
            RuleEditorView(store: store, gate: gate, existing: editingRule) { showingEditor = false }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule")
                    .font(Theme.displayFont(24, .bold))
                    .foregroundStyle(Theme.mist)
                Text("When the distractions go dark, automatically.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mistDim)
            }
            Spacer()
            Button {
                editingRule = nil; showingEditor = true
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ember)
        }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { idx, label in
                HStack(spacing: Theme.Spacing.s) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.mistDim)
                        .frame(width: 34, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.inkRaised)
                            ForEach(spans(forWeekday: idx + 1), id: \.id) { span in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Theme.ember.opacity(0.8))
                                    .frame(width: max(2, geo.size.width * span.fraction))
                                    .offset(x: geo.size.width * span.start)
                            }
                        }
                    }
                    .frame(height: 18)
                }
            }
            HStack(spacing: Theme.Spacing.s) {
                Spacer().frame(width: 34)
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text("\(hour):00").font(.system(size: 9)).foregroundStyle(Theme.mistDim)
                        if hour != 24 { Spacer() }
                    }
                }
            }
        }
        .card()
    }

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if store.config.rules.isEmpty {
                Text("No rules yet. Add one to start blocking on a schedule.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mistDim)
            }
            ForEach(store.config.rules, id: \.id) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeRange(rule))
                            .font(Theme.monoFont(13))
                            .foregroundStyle(Theme.mist)
                        Text(blockSetNames(rule.blockSetIds))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mistDim)
                    }
                    Spacer()
                    Button {
                        editingRule = rule; showingEditor = true
                    } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .disabled(statusModel.isActive)
                    Button(role: .destructive) {
                        store.removeRule(id: rule.id)
                        Task { _ = await store.commit() }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .disabled(statusModel.isActive)
                }
                .padding(Theme.Spacing.m)
                .background(Theme.inkSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func blockSetNames(_ ids: [String]) -> String {
        let names = ids.compactMap { id in store.config.blockSets.first { $0.id == id }?.name }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private func timeRange(_ r: Rule) -> String {
        String(format: "%02d:%02d – %02d:%02d", r.startHour, r.startMinute, r.endHour, r.endMinute)
    }

    private struct Span: Identifiable { let id = UUID(); let start: Double; let fraction: Double }

    private func spans(forWeekday wd: Int) -> [Span] {
        var result: [Span] = []
        for rule in store.config.rules where rule.weekdays.contains(wd) {
            let startMin = Double(rule.startHour * 60 + rule.startMinute)
            let endMin = Double(rule.endHour * 60 + rule.endMinute)
            let day = 1440.0
            if endMin > startMin {
                result.append(Span(start: startMin / day, fraction: (endMin - startMin) / day))
            } else {
                result.append(Span(start: startMin / day, fraction: (day - startMin) / day))
                result.append(Span(start: 0, fraction: endMin / day))
            }
        }
        return result
    }
}
