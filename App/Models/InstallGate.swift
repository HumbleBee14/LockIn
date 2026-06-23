import Foundation

// Verifies the helper is installed at the moment of every lock-creating action. If not, it surfaces
// the install sheet and runs the pending action once the helper becomes ready. Re-checks live each
// time, so a helper removed later is caught on the next attempt.
@MainActor
final class InstallGate: ObservableObject {
    @Published var showingInstall = false
    let installer = InstallerService()

    private var pendingAction: (() async -> Void)?

    func require(_ action: @escaping () async -> Void) {
        if installer.isReady() {
            Task { await action() }
        } else {
            pendingAction = action
            showingInstall = true
        }
    }

    // called by the install sheet whenever status changes; runs the pending action once ready
    func resolveIfReady() {
        guard installer.isReady(), let action = pendingAction else { return }
        pendingAction = nil
        showingInstall = false
        Task { await action() }
    }

    func cancel() {
        pendingAction = nil
        showingInstall = false
    }
}
