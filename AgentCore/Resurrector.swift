import Foundation
import ServiceManagement

// Tier 5c — best-effort only. KeepAlive (launchd) is the real resurrection mechanism. This never
// gates correctness and no test depends on it: booting out a system daemon needs sudo (past our
// threat ceiling), and SMAppService re-registration generally wants the app's bundle context.
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
