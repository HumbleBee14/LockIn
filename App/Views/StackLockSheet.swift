import SwiftUI

// the ONLY surface reachable while locked besides the lock screen itself: pick existing blocklist
// sets or create a brand-new one (create-only — existing sets stay untouchable during any lock),
// then either stack a quick lock now or save a repeating schedule rule for those sets.
struct StackLockSheet: View {
    enum Mode: String, CaseIterable { case quick = "Quick lock", schedule = "Schedule" }

    @ObservedObject var store: ScheduleStore
    @ObservedObject var statusModel: StatusViewModel
    var onScheduled: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .quick
    @State private var selectedIds: Set<String> = []
    @State private var durationMinutes = 60
    @State private var customMode = false
    @State private var customMinutes: Double = 60
    @State private var window = ScheduleWindow.upcoming()
    @State private var starting = false
    @State private var failReason: String?
    @State private var syncWarning: (summary: String, text: String)?
    @State private var showCreate = false
    @State private var newSetName = ""
    @State private var newSetDomains = ""

    private let presets: [(String, Int)] = [("30 min", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240)]
    private let maxMinutes = 22.0 * 60

    // invariant (Law 3): only blocklist sets are offered here, in both modes — an allowlist can never be armed while locked
    private var blocklistSets: [BlockSet] { store.config.blockSets.filter { $0.mode == .blocklist } }
    private var effectiveMinutes: Int { customMode ? Int(customMinutes.rounded()) : durationMinutes }
    private var selectedDomainCount: Int {
        var seen = Set<String>()
        for set in blocklistSets where selectedIds.contains(set.id) { seen.formUnion(set.domains) }
        return seen.count
    }
    // the daemon refuses an over-cap set at fire time with no way to say so from a schedule, so refuse here
    private var hasUsableSelection: Bool {
        selectedDomainCount > 0 && selectedDomainCount <= BlockLimits.maxActiveDomains
    }
    private var canStart: Bool {
        !starting && hasUsableSelection && (mode == .quick || window.isValid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .top) {
                Text("Add another lock")
                    .font(Theme.displayFont(18, .semibold)).foregroundStyle(Theme.mist)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mistDim)
                        .frame(width: 26, height: 26)
                        .background(Theme.inkRaised)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            modeToggle
            Text(subtitle)
                .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
                .fixedSize(horizontal: false, vertical: true)

            switch mode {
            case .quick: durationPicker
            case .schedule: ScheduleWindowPicker(window: $window)
            }

            setsSection
            startButton
        }
        .padding(Theme.Spacing.l)
        .frame(width: 460)
        .onAppear { showCreate = blocklistSets.isEmpty }
        .alert(mode == .quick ? "Couldn’t start the lock" : "Couldn’t save the schedule", isPresented: Binding(
            get: { failReason != nil }, set: { if !$0 { failReason = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failReason ?? "") }
        .alert("Saved, but not confirmed yet", isPresented: Binding(
            get: { syncWarning != nil }, set: { if !$0 { syncWarning = nil } })) {
            Button("OK", role: .cancel) {
                if let syncWarning { onScheduled(syncWarning.summary) }
                dismiss()
            }
        } message: { Text(syncWarning?.text ?? "") }
    }

    private var subtitle: String {
        switch mode {
        case .quick:
            return "Stacks on top of what's already locked — it can only block more, and can't be turned off until it ends."
        case .schedule:
            return "Saves a repeating schedule. If its window is open right now it starts within a few seconds, stacked on top of what's already locked."
        }
    }

    // frozen while a start/save is in flight so the button label and alert title can't drift mid-request
    private var modeToggle: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Mode.allCases, id: \.self) { m in
                chip(m.rawValue, selected: mode == m) { mode = m }
            }
        }
        .disabled(starting)
    }

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("What to block").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
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
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("New block set").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                Spacer()
                // no way back out otherwise; only offer it when an existing set is available to fall back to
                if !blocklistSets.isEmpty {
                    Button("Cancel") {
                        newSetName = ""; newSetDomains = ""; showCreate = false
                    }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.mistDim)
                }
            }
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
            HStack {
                Text("For how long").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mistDim)
                Spacer()
                Text(Self.durationLabel(effectiveMinutes))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ember)
                    .monospacedDigit()
            }
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(presets, id: \.1) { preset in
                    chip(preset.0, selected: !customMode && durationMinutes == preset.1) {
                        customMode = false; durationMinutes = preset.1
                    }
                }
                chip("Custom", selected: customMode) { customMode = true }
            }
            if customMode {
                // custom themed track — the native Slider draws a harsh light track on dark backgrounds
                themedSlider
            }
        }
    }

    // dark-themed replacement for the native Slider (whose track renders as a harsh light line here)
    private var themedSlider: some View {
        let knob: CGFloat = 18, track: CGFloat = 4
        return GeometryReader { geo in
            let usable = max(1, geo.size.width - knob)
            let frac = (customMinutes - 1) / (maxMinutes - 1)   // 0…1
            let x = CGFloat(frac) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.inkRaised).frame(height: track)
                Capsule().fill(Theme.ember).frame(width: x + knob / 2, height: track)
                Circle().fill(.white).frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: x)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let clamped = min(max(0, value.location.x - knob / 2), usable)
                let m = 1 + Double(clamped / usable) * (maxMinutes - 1)
                customMinutes = m.rounded()
            })
        }
        .frame(height: knob)
    }

    // "45 min" under an hour, "1:30" for hours+minutes, "2 hours" on the hour
    static func durationLabel(_ minutes: Int) -> String {
        let m = max(1, minutes)
        if m < 60 { return "\(m) min" }
        let h = m / 60, rem = m % 60
        if rem == 0 { return h == 1 ? "1 hour" : "\(h) hours" }
        return String(format: "%d:%02d", h, rem)
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

    private var buttonTitle: String {
        switch mode {
        case .quick: return starting ? "Starting…" : "Start Lock"
        case .schedule: return starting ? "Saving…" : "Save Schedule"
        }
    }

    private var startButton: some View {
        Button {
            switch mode {
            case .quick: start()
            case .schedule: saveSchedule()
            }
        } label: {
            Text(buttonTitle)
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

    // same path the Schedule tab takes: a plain Rule in config, pushed with the regular commit.
    // the daemon's reconcile tick then arms it — immediately if the window is already open.
    private func saveSchedule() {
        let rule = window.rule(id: UUID().uuidString, blockSetIds: Array(selectedIds))
        let summary = window.summary()   // describe what was saved, not what the picker shows after the await
        // pressing Save twice must not arm two copies of the same rule (each would be its own snapshot)
        if store.config.rules.contains(where: { Self.sameWindow($0, rule) }) {
            onScheduled(summary)
            dismiss()
            return
        }
        starting = true
        Task {
            store.addRule(rule)
            let accepted = await store.commit()
            starting = false
            if accepted {
                onScheduled(summary)
                dismiss()
            } else {
                // a false reply means the daemon didn't confirm, not that it didn't save (the reply itself can
                // be lost). keep the rule: the next commit re-sends the whole config (spec D5), whereas removing
                // it could orphan a copy only the daemon knows about.
                syncWarning = (summary, "The schedule is saved in LockIn, but the blocker didn’t confirm it. "
                    + "It syncs the next time LockIn talks to the blocker.")
            }
        }
    }

    private static func sameWindow(_ a: Rule, _ b: Rule) -> Bool {
        Set(a.weekdays) == Set(b.weekdays) && Set(a.blockSetIds) == Set(b.blockSetIds)
            && a.startHour == b.startHour && a.startMinute == b.startMinute
            && a.endHour == b.endHour && a.endMinute == b.endMinute
    }
}
