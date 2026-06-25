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

    // invariant: every outcome sets a visible message — never fail silently
    func install() async {
        let alive = await client.ping()
        installer.registerAll(daemonAlive: alive)
        if installer.lastError != nil { return }
        guard installer.isReady() else {
            installer.lastError = "Install didn't take — the blocker isn't registered. Try again."
            return
        }
        guard await pingWithRetry() else {
            installer.lastError = "Installed, but the blocker isn't responding yet. Wait a moment and try again."
            return
        }
        installer.lastError = nil
        showingInstall = false
        let action = pendingAction
        pendingAction = nil
        await action?()
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

    // called by the install sheet whenever status changes; runs the pending action once ready
    func resolveIfReady() {
        // once the daemon is approved, register the agent on this tick (can't be done in the same tick as the daemon)
        installer.registerAgentIfDaemonReady()
        Task {
            guard await isReady(), let action = pendingAction else { return }
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
