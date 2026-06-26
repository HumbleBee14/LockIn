import Foundation
import Darwin

protocol AppBlocking {
    func update(active: Bool, bundleIds: [String])
    func isMonitoring() -> Bool
    func sweepNow()
}

// invariant: app-killing runs in the root daemon, never a user agent (a system daemon can't reach the gui-session agent)
final class AppBlocker: AppBlocking, @unchecked Sendable {
    private let lock = NSLock()
    private var blocked: Set<String> = []
    private var timer: DispatchSourceTimer?

    // invariant: never kill LockIn's own bundle family — a self-block would brick the app in a relaunch loop
    static let neverKill: Set<String> = [
        "com.humblebee.lockin", "com.humblebee.lockin.agent",
        "com.humblebee.lockin.daemon", "com.humblebee.lockin.notifier"
    ]

    private let pollInterval: DispatchTimeInterval = .milliseconds(1000)
    private let pollLeeway: DispatchTimeInterval = .milliseconds(100)

    func update(active: Bool, bundleIds: [String]) {
        lock.lock()
        blocked = active ? Set(bundleIds).subtracting(Self.neverKill) : []
        let shouldRun = !blocked.isEmpty
        let running = timer != nil
        lock.unlock()

        if shouldRun && !running { startMonitoring() }
        else if !shouldRun && running { stopMonitoring() }
        else if shouldRun { sweepNow() }
    }

    func isMonitoring() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return timer != nil
    }

    func sweepNow() {
        findAndKillBlockedApps()
    }

    private func startMonitoring() {
        findAndKillBlockedApps()
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: pollLeeway)
        t.setEventHandler { [weak self] in self?.findAndKillBlockedApps() }
        lock.lock(); timer = t; let n = blocked.count; lock.unlock()
        t.resume()
        LockInLog.info("AppBlocker monitoring \(n) apps")
    }

    private func stopMonitoring() {
        lock.lock(); let t = timer; timer = nil; lock.unlock()
        t?.cancel()
        LockInLog.info("AppBlocker stopped")
    }

    private func findAndKillBlockedApps() {
        lock.lock(); let targets = blocked; lock.unlock()
        guard !targets.isEmpty else { return }

        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size)
        count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let n = Int(count) / MemoryLayout<pid_t>.size

        for i in 0..<n {
            let pid = pids[i]
            guard pid != 0 else { continue }
            guard let bid = bundleID(forPID: pid), targets.contains(bid),
                  !Self.neverKill.contains(bid) else { continue }
            if kill(pid, SIGTERM) != 0 {
                if kill(pid, SIGKILL) != 0 {
                    LockInLog.error("AppBlocker kill failed for \(bid) pid \(pid) errno \(errno)")
                    continue
                }
            }
            LockInLog.info("AppBlocker terminated \(bid) pid \(pid)")
        }
    }

    private static let maxPathSize = 4096

    private func bundleID(forPID pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Self.maxPathSize)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return nil }
        let execPath = String(cString: buf)
        var path = execPath as NSString
        while path.length > 1 {
            if path.hasSuffix(".app") {
                let plist = path.appendingPathComponent("Contents/Info.plist")
                guard let info = NSDictionary(contentsOfFile: plist),
                      let bid = info["CFBundleIdentifier"] as? String else { return nil }
                return bid
            }
            path = path.deletingLastPathComponent as NSString
        }
        return nil
    }
}
