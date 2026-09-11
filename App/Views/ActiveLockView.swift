import SwiftUI

struct ActiveLockView: View {
    @ObservedObject var model: StatusViewModel
    @ObservedObject var store: ScheduleStore

    @State private var now = Date()
    @State private var newDomain = ""
    @State private var showingStackSheet = false
    @State private var appendFailReason: String?
    @State private var scheduledNote: String?
    @State private var scheduledNoteTimer: Task<Void, Never>?
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
                    showingStackSheet = true
                } label: {
                    Label("New Lock", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .tint(Theme.ember)
            }

            if let scheduledNote {
                scheduledConfirmation(scheduledNote)
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
        .onDisappear { scheduledNoteTimer?.cancel() }
        .sheet(isPresented: $showingStackSheet) {
            StackLockSheet(store: store, statusModel: model, onScheduled: showScheduled)
        }
        .alert("Couldn’t add the site", isPresented: Binding(
            get: { appendFailReason != nil }, set: { if !$0 { appendFailReason = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(appendFailReason ?? "") }
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
        scheduledNote = "Scheduled · \(summary)"
        scheduledNoteTimer?.cancel()   // a second save restarts the clock instead of being cut short by the first
        scheduledNoteTimer = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            scheduledNote = nil
        }
    }

    private func scheduledConfirmation(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 12)).foregroundStyle(Theme.sage)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.mist)
        }
        .padding(.vertical, 6).padding(.horizontal, Theme.Spacing.m)
        .background(Theme.sage.opacity(0.12))
        .clipShape(Capsule())
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
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: 420)
    }

    private func add() {
        let parsed = ScheduleStore.parseDomainList(newDomain)
        guard !parsed.isEmpty else { return }
        newDomain = ""
        Task {
            if let reason = await model.addDomains(parsed, persistingTo: store) {
                appendFailReason = reason
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
