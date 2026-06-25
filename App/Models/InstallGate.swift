import Foundation

// invariant: readiness needs a live daemon ping, not just SMAppService's status (which goes stale)
@MainActor
final class InstallGate: ObservableObject {
    @Published var showingInstall = false
    @Published var resolving = false
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

    func resolveIfReady() {
        guard !resolving else { return }
        resolving = true
        installer.lastError = nil
        Task {
            defer { resolving = false }
            guard installer.isReady() else {
                installer.lastError = "Website blocking isn’t approved yet. Tap Approve above, then allow it in System Settings."
                return
            }
            if await pingWithRetry() == false {
                installer.registerDaemon(alive: false)
                guard await pingWithRetry() else {
                    installer.lastError = "Couldn’t start the background service. Quit LockIn and reopen it; if it persists, restart your Mac."
                    return
                }
            }
            showingInstall = false
            if let action = pendingAction {
                pendingAction = nil
                await action()
            }
        }
    }

    func forceReinstall() {
        installer.unregisterAll()
        showingInstall = true
    }

    func cancel() {
        pendingAction = nil
        showingInstall = false
    }
}
