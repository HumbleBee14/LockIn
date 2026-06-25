import Foundation
import AppKit

public final class LaunchObserver {
    // invariant: snapshot is read on the main-queue launch handler and written from the XPC queue;
    // the lock makes that access a non-race (Swift 6 strict concurrency would otherwise reject it).
    private let lock = NSLock()
    private var _snapshot = BlockedAppSnapshot(active: false, bundleIds: [])
    private var snapshot: BlockedAppSnapshot {
        get { lock.lock(); defer { lock.unlock() }; return _snapshot }
        set { lock.lock(); _snapshot = newValue; lock.unlock() }
    }
    private var token: NSObjectProtocol?

    public init() {}

    public func updateSnapshot(_ s: BlockedAppSnapshot) {
        snapshot = s
        sweepRunningApps()
    }

    public func shouldTerminate(bundleId: String) -> Bool {
        let s = snapshot
        return s.active && s.bundleIds.contains(bundleId)
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
