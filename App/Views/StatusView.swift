import SwiftUI

struct StatusView: View {
    @ObservedObject var model: StatusViewModel
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                StatusRing(active: model.isActive,
                           centerText: ringCenter,
                           caption: ringCaption)
                    .frame(width: 240, height: 240)
                    .padding(.top, Theme.Spacing.xl)

                if model.isActive {
                    VStack(spacing: Theme.Spacing.m) {
                        Disclosures.cannotCancel
                        if let domains = model.status?.appliedDomains, !domains.isEmpty {
                            blockedSummary(domains)
                        }
                    }
                    .frame(maxWidth: 460)
                } else {
                    Text(model.status?.nextTriggerDescription.map { "Next block \($0)" }
                            ?? "No upcoming blocks scheduled")
                        .font(Theme.displayFont(15, .medium))
                        .foregroundStyle(Theme.mistDim)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.l)
        }
        .onReceive(tick) { now = $0 }
        .task { await model.refresh() }
    }

    private var ringCenter: String {
        guard model.isActive, let end = model.status?.windowEnd else { return "Armed" }
        _ = now
        return model.countdown(to: end)
    }

    private var ringCaption: String {
        model.isActive ? "until your window ends" : "ready when the schedule fires"
    }

    private func blockedSummary(_ domains: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Blocking \(domains.count) destination\(domains.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.mist)
            Text(domains.prefix(6).joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.mistDim)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct StatusRing: View {
    let active: Bool
    let centerText: String
    let caption: String

    private var ringColor: Color { active ? Theme.ember : Theme.sage }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.inkRaised, lineWidth: 14)
            Circle()
                .trim(from: 0, to: active ? 1 : 0.001)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.5), radius: active ? 18 : 0)
            if !active {
                Circle()
                    .stroke(ringColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
                    .padding(7)
            }
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
        .animation(.easeInOut(duration: 0.4), value: active)
    }
}
