import Foundation
import ServiceManagement

@MainActor
final class InstallerService: ObservableObject {
    @Published var daemonStatus: SMAppService.Status = .notRegistered
    @Published var agentStatus: SMAppService.Status = .notRegistered

    @Published var lastError: String?

    private let daemon = SMAppService.daemon(plistName: "lockind.plist")
    private let agent = SMAppService.agent(plistName: "lockin-agent.plist")

    // the daemon (website blocking) gates a lock; the agent (app blocking) is best-effort and never blocks it
    func isReady() -> Bool {
        refreshStatus()
        return daemonStatus == .enabled
    }

    func unregisterAll() {
        do { try daemon.unregister() } catch { LockInLog.error("daemon.unregister failed", error) }
        do { try agent.unregister() } catch { LockInLog.error("agent.unregister failed", error) }
        refreshStatus()
        LockInLog.info("unregisterAll done — daemon=\(Self.describe(daemonStatus)) agent=\(Self.describe(agentStatus))")
    }

    // invariant: never clear a registration while a lock could be live (daemonAlive); only the owning app may unregister
    func reconcileStaleRegistration(daemonAlive: Bool) {
        refreshStatus()
        guard daemonStatus == .enabled, !daemonAlive else { return }
        LockInLog.info("reconcile: daemon .enabled but not alive — clearing stale registration")
        do { try daemon.unregister() } catch { LockInLog.error("reconcile daemon.unregister failed", error) }
        do { try agent.unregister() } catch { LockInLog.error("reconcile agent.unregister failed", error) }
        refreshStatus()
    }

    // the agent registers cleanly only after the daemon is approved; called repeatedly by the poll
    func registerAgentIfDaemonReady() {
        refreshStatus()
        guard daemonStatus == .enabled else { return }
        if agentStatus == .notRegistered || agentStatus == .notFound {
            do { try agent.register() } catch { LockInLog.error("agent.register failed", error) }
            refreshStatus()
        }
    }

    // required website-blocking helper; re-registers a stale enabled job that no longer answers
    func registerDaemon(alive: Bool) {
        refreshStatus()
        LockInLog.info("registerDaemon(alive: \(alive)) — current status=\(Self.describe(daemonStatus))")
        if daemonStatus == .enabled && !alive {
            do { try daemon.unregister() }
            catch { LockInLog.error("daemon.unregister (stale) failed", error); lastError = humanError(error); return }
            refreshStatus()
        }
        if daemonStatus == .enabled {
            lastError = "macOS reports the service as installed but it isn’t running — its background record is out of sync. Restart your Mac to rebuild it."
            LockInLog.error("daemon enabled but not alive — launchd job desynced from registration")
            openLoginItems()
            return
        }
        do {
            try daemon.register()
            LockInLog.info("daemon.register() succeeded — status now \(Self.describe(daemon.status))")
        } catch {
            LockInLog.error("daemon.register() failed", error)
            lastError = humanError(error)
        }
        refreshStatus()
    }

    // one OS background-activity toggle covers both helpers; the agent follows once the daemon is enabled
    func approveAll(daemonAlive: Bool) {
        registerDaemon(alive: daemonAlive)
        registerAgentIfDaemonReady()
    }

    // optional app-blocking helper; needs the daemon approved first so its prompt doesn't collide
    func registerAgent() {
        refreshStatus()
        if agentStatus == .enabled { openLoginItems(); return }
        guard daemonStatus == .enabled else {
            lastError = "Approve website blocking first, then app blocking."
            return
        }
        do { try agent.register() } catch { lastError = humanError(error) }
        refreshStatus()
    }

    func refreshStatus() {
        daemonStatus = daemon.status
        agentStatus = agent.status
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "Not installed"
        case .enabled: return "Active"
        case .requiresApproval: return "Waiting for approval"
        case .notFound: return "Registering…"
        @unknown default: return "Unknown"
        }
    }

    private func humanError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "SMAppServiceErrorDomain" && ns.code == 1 {
            return "macOS blocked registration (a previous install is stuck). Restart your Mac, then open LockIn again. (\(ns.domain) \(ns.code))"
        }
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
    }
}
