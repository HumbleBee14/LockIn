import Foundation
import ServiceManagement

// tier 5c — best-effort only; launchd KeepAlive is the real mechanism. No test depends on this.
public final class Resurrector {
    private let daemonPing: () -> Bool
    private var lastAttempt: Date?
    private let minInterval: TimeInterval = 60

    public init(daemonPing: @escaping () -> Bool) {
        self.daemonPing = daemonPing
    }

    public func tickIfBlockActive(_ active: Bool, now: Date) {
        guard active, !daemonPing() else { return }
        if let last = lastAttempt, now.timeIntervalSince(last) < minInterval { return }
        lastAttempt = now
        try? SMAppService.daemon(plistName: "lockind.plist").register()
    }
}
