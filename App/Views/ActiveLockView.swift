import SwiftUI
import Combine

struct ActiveLockView: View {
    @ObservedObject var model: StatusViewModel
    @ObservedObject var store: ScheduleStore

    @State private var now = Date()
    @State private var newDomain = ""
    @State private var showingStackSheet = false
    @State private var appendFailReason: String?
    @State private var appendWarning: String?
    @State private var note: (icon: String, text: String)?
    @State private var noteTimer: Task<Void, Never>?
    @State private var targetSetId: String?
    @State private var adding = false
    @State private var stackSheetCreating = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            StatusRing(active: true, centerText: countdown, caption: caption)
                .frame(width: 240, height: 240)

            VStack(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(model.status?.blockSetTitle ?? "Locked")
                        .font(Theme.displayFont(18, .semibold)).foregroundStyle(Theme.mist)
                    enforcementDot
                }
                Text(identity)
                    .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
            }

            if let locks = model.status?.locks, locks.count > 1 {
                lockList(locks)
            }

            if model.canStackLock {
                Button {
                    stackSheetCreating = false
                    showingStackSheet = true
                } label: {
                    Label("New Lock", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .tint(Theme.ember)
            }

            if let note {
                confirmation(icon: note.icon, text: note.text)
            }

            if let skipped = model.status?.skippedScheduleTitles, !skipped.isEmpty {
                DisclosureCallout(icon: "exclamationmark.triangle.fill", tint: Theme.amber,
                    title: "Waiting to start: \(skipped.joined(separator: ", "))",
                    message: "Together with what's already locked it would pass the \(BlockLimits.maxActiveDomains) site limit. It starts automatically once enough locks end.")
                    .frame(maxWidth: 420)
            }

            if model.canAddDomains {
                addDomainField
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .background(Theme.inkBase)
        .onReceive(tick) { now = $0 }
        .onDisappear { noteTimer?.cancel() }
        .sheet(isPresented: $showingStackSheet) {
            StackLockSheet(store: store, statusModel: model, startCreating: stackSheetCreating,
                           onScheduled: showScheduled)
        }
        .alert("Couldn’t add the site", isPresented: Binding(
            get: { appendFailReason != nil }, set: { if !$0 { appendFailReason = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(appendFailReason ?? "") }
        .alert("Added, but not fully saved", isPresented: Binding(
            get: { appendWarning != nil }, set: { if !$0 { appendWarning = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(appendWarning ?? "") }
    }

    // both layers live = solid green; hosts-only (pf not confirmed) = amber. internal signal, no label.
    private var enforcementDot: some View {
        let full = model.status?.pfApplied ?? false
        return Circle()
            .fill(full ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
            .help(full ? "Fully enforced" : "Partially enforced")
    }

    private var countdown: String {
        guard let end = model.status?.endsAt else { return "Locked" }
        _ = now
        return model.countdown(to: end)
    }

    private var caption: String {
        guard let end = model.status?.endsAt else { return "until your block ends" }
        _ = now
        return "ends at \(model.endTimeString(end))"
    }

    private var identity: String {
        let source = model.status?.source == "quick" ? "Quick Lock" : "Scheduled"
        let mode = (model.status?.isAllowlist ?? false) ? "Allow-only" : "Blocklist"
        return "\(source) · \(mode)"
    }

    // a rule saved from the sheet may not be due yet, so nothing else on this screen would change —
    // confirm it briefly (the schedule itself lives in the Schedule tab once the lock ends)
    private func showScheduled(_ summary: String) {
        showNote(icon: "calendar.badge.checkmark", text: "Scheduled · \(summary)")
    }

    private func showNote(icon: String, text: String) {
        note = (icon, text)
        noteTimer?.cancel()   // a second note restarts the clock instead of being cut short by the first
        noteTimer = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            note = nil
        }
    }

    private func confirmation(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 12)).foregroundStyle(Theme.sage)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.mist)
        }
        .padding(.vertical, 6).padding(.horizontal, Theme.Spacing.m)
        .background(Theme.sage.opacity(0.12))
        .clipShape(Capsule())
    }

    // invariant (Law 3): only blocklist sets can receive a site mid-lock — adding to an allowlist would unblock it
    private var blocklistSets: [BlockSet] { store.config.blockSets.filter { $0.mode == .blocklist } }
    private var lockedSetIds: Set<String> { Set(model.activeBlocklistLocks.flatMap(\.allBlockSetIds)) }

    // the user's pick, else the set the daemon would have used anyway, else any locked set
    private var targetSet: BlockSet? {
        let ids = [targetSetId, model.status?.appendTargetBlockSetId].compactMap { $0 }
        for id in ids { if let set = blocklistSets.first(where: { $0.id == id }) { return set } }
        return blocklistSets.first { lockedSetIds.contains($0.id) } ?? blocklistSets.first
    }
    private var canAdd: Bool {
        !adding && targetSet != nil && !newDomain.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var addDomainField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Found another site to block? Add it (can't remove during a lock).")
                .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
            HStack {
                TextField("example.com", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add") { add() }.tint(Theme.ember)
                    .disabled(!canAdd)
            }
            targetPicker
        }
        .frame(maxWidth: 420)
    }

    // existing sets can only grow here; making a new set routes to the same sheet as "+ New Lock"
    private var targetPicker: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Add to").font(.system(size: 11)).foregroundStyle(Theme.mistDim)
            Menu {
                let locked = blocklistSets.filter { lockedSetIds.contains($0.id) }
                let others = blocklistSets.filter { !lockedSetIds.contains($0.id) }
                if !locked.isEmpty {
                    SwiftUI.Section("Locked now") { ForEach(locked, id: \.id) { targetOption($0) } }
                }
                if !others.isEmpty {
                    SwiftUI.Section("Other block sets") { ForEach(others, id: \.id) { targetOption($0) } }
                }
                if model.canStackLock {
                    Divider()
                    Button("New block set…") {
                        stackSheetCreating = true
                        showingStackSheet = true
                    }
                }
            } label: {
                Text(targetSet?.name ?? "Choose a block set")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .tint(Theme.ember)
            Spacer()
        }
    }

    private func targetOption(_ set: BlockSet) -> some View {
        Button {
            targetSetId = set.id
        } label: {
            if set.id == targetSet?.id { Label(set.name, systemImage: "checkmark") } else { Text(set.name) }
        }
    }

    private func add() {
        guard canAdd, let set = targetSet else { return }
        let parsed = ScheduleStore.parseDomainList(newDomain)
        guard !parsed.isEmpty else { return }
        adding = true
        Task {
            defer { adding = false }
            switch await model.addDomains(parsed, toBlockSet: set.id, persistingTo: store) {
            case .failed(let reason):
                appendFailReason = reason
            case .added(let until, let warning):
                newDomain = ""
                targetSetId = set.id
                let end = until.map { " · blocked until \(model.endTimeString($0))" } ?? ""
                showNote(icon: "checkmark.circle", text: "Added to \(set.name)\(end)")
                appendWarning = warning
            }
        }
    }

    private func lockList(_ locks: [ActiveLockInfo]) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(locks.sorted { $0.endsAt < $1.endsAt }, id: \.id) { lock in
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: lock.source == "quick" ? "bolt.shield" : "calendar")
                        .font(.system(size: 11)).foregroundStyle(Theme.mistDim)
                    Text(lock.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.mist)
                    Spacer()
                    Text("ends \(model.endTimeString(lock.endsAt))")
                        .font(Theme.monoFont(11, .regular)).foregroundStyle(Theme.mistDim)
                }
                .padding(.vertical, 6).padding(.horizontal, Theme.Spacing.s)
                .background(Theme.inkRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: 420)
    }
}

struct StatusRing: View {
    let active: Bool
    let centerText: String
    let caption: String

    private var ringColor: Color { active ? Theme.ember : Theme.sage }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.inkRaised, lineWidth: 14)
            Circle()
                .trim(from: 0, to: active ? 1 : 0.001)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.5), radius: active ? 18 : 0)
            VStack(spacing: Theme.Spacing.xs) {
                Text(centerText)
                    .font(Theme.monoFont(active ? 38 : 28, .semibold))
                    .foregroundStyle(Theme.mist)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.mistDim)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
    }
}

#if DEBUG
// design-time only: fake locks and sets, no daemon involved (an Add here just fails to reach the blocker)
#Preview("Lock screen · stacked") {
    let sets = [
        BlockSet(id: "ad", name: "AD+", domains: ["ads.example"], appBundleIds: [], mode: .blocklist),
        BlockSet(id: "social", name: "Social", domains: ["x.com"], appBundleIds: [], mode: .blocklist),
        BlockSet(id: "random", name: "Random", domains: ["reddit.com"], appBundleIds: [], mode: .blocklist),
    ]
    let client = DaemonClient()
    let store = ScheduleStore(client: client, config: ScheduleConfig(rules: [], blockSets: sets))
    let model = StatusViewModel(client: client)
    let locks = [
        ActiveLockInfo(id: "q1", title: "AD+", source: "scheduled", endsAt: Date().addingTimeInterval(5 * 3600),
                       isAllowlist: false, blockSetId: "ad", domainCount: 1),
        ActiveLockInfo(id: "q2", title: "Social", source: "quick", endsAt: Date().addingTimeInterval(3600),
                       isAllowlist: false, blockSetId: "social", domainCount: 1),
    ]
    model.status = DaemonStatus(active: true, source: "scheduled", blockSetId: "ad", blockSetTitle: "AD+ +1",
                                isAllowlist: false, endsAt: locks[0].endsAt, appliedDomains: [],
                                nextTriggerDescription: nil, pfApplied: true, locks: locks,
                                appendTargetBlockSetId: "ad")
    return ActiveLockView(model: model, store: store).frame(width: 700, height: 760)
}
#endif
