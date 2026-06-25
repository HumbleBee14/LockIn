import Foundation

// invariant: readiness needs a live daemon ping, not just SMAppService's status (which goes stale)
@MainActor
final class InstallGate: ObservableObject {
    @Published var showingInstall = false
    let installer = InstallerService()
    private let client = DaemonClient()

    private var pendingAction: (() async -> Void)?

    private func isReady() async -> Bool {
        guard installer.isReady() else { return false }
        return await client.ping()
    }

    // approve the required website-blocking helper; the poll resolves the pending action once it's live
    func approveDaemon() async {
        installer.lastError = nil
        let alive = await client.ping()
        installer.registerDaemon(alive: alive)
    }

    private func pingWithRetry(attempts: Int = 5) async -> Bool {
        for _ in 0..<attempts {
            if await client.ping() { return true }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        return false
    }

    func require(_ action: @escaping () async -> Void) {
        Task {
            if await isReady() {
                await action()
            } else {
                pendingAction = action
                showingInstall = true
            }
        }
    }

    // runs the pending action once the required daemon is live; called by Continue and the poll
    func resolveIfReady() {
        guard installer.isReady() else { return }
        Task {
            guard await pingWithRetry(), let action = pendingAction else { return }
            pendingAction = nil
            installer.lastError = nil
            showingInstall = false
            await action()
        }
    }

    func cancel() {
        pendingAction = nil
        showingInstall = false
    }
}
