import SwiftUI

struct DaemonUnreachableView: View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.inkBase)
    }
}
