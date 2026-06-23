import Foundation
import AppKit

public final class LaunchObserver {
    private var snapshot = BlockedAppSnapshot(active: false, bundleIds: [])
    private var token: NSObjectProtocol?

    public init() {}

    public func updateSnapshot(_ s: BlockedAppSnapshot) {
        snapshot = s
        sweepRunningApps()
    }

    public func shouldTerminate(bundleId: String) -> Bool {
        snapshot.active && snapshot.bundleIds.contains(bundleId)
    }

    // didLaunch misses apps already open at block start, so sweep them here
    private func sweepRunningApps() {
        guard snapshot.active else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, shouldTerminate(bundleId: bid) { kill(app) }
        }
    }

    public func start() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier, self.shouldTerminate(bundleId: bid) else { return }
            self.kill(app)
        }
    }

    private func kill(_ app: NSRunningApplication) {
        // soft deterrent: escalate to forceTerminate if the app defers terminate
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if !app.isTerminated { app.forceTerminate() }
        }
    }

    public func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
