import SwiftUI

struct DaemonUnreachableView: View {
    let onReconnect: () -> Void
    @State private var elapsed = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40)).foregroundStyle(Theme.ember)
            Text("Reconnecting…")
                .font(Theme.displayFont(20, .bold)).foregroundStyle(Theme.mist)
            Text("LockIn can’t reach its background service right now. A lock may still be active, so controls stay hidden until it reconnects.")
                .font(.system(size: 13)).foregroundStyle(Theme.mistDim)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            ProgressView().controlSize(.small)

            if elapsed >= 8 {
                VStack(spacing: Theme.Spacing.s) {
                    Text("Still not connecting?")
                        .font(.system(size: 12)).foregroundStyle(Theme.mistDim)
                    Button("Set up again") { onReconnect() }
                        .buttonStyle(.borderedProminent).tint(Theme.ember)
                }
                .padding(.top, Theme.Spacing.m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.inkBase)
        .onReceive(tick) { _ in elapsed += 1 }
    }
}
