import SwiftUI

struct ActiveLockView: View {
    @ObservedObject var model: StatusViewModel
    @ObservedObject var store: ScheduleStore

    @State private var now = Date()
    @State private var newDomain = ""
    @State private var showingCapAlert = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            StatusRing(active: true, centerText: countdown, caption: caption)
                .frame(width: 240, height: 240)

            VStack(spacing: Theme.Spacing.xs) {
                Text(model.status?.blockSetTitle ?? "Locked")
                    .font(Theme.displayFont(18, .semibold)).foregroundStyle(Theme.mist)
                Text(identity)
                    .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
            }

            if model.canAddDomains {
                addDomainField
            }

            Disclosures.cannotCancel.frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .background(Theme.inkBase)
        .onReceive(tick) { now = $0 }
        .alert("List is full", isPresented: $showingCapAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This block already holds the maximum of \(BlockLimits.maxActiveDomains) sites.")
        }
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
        if (model.status?.appliedDomains.count ?? 0) >= BlockLimits.maxActiveDomains {
            showingCapAlert = true; newDomain = ""; return
        }
        newDomain = ""
        Task { _ = await model.addDomains(parsed, persistingTo: store) }
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
