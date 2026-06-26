import Foundation
import LockInDaemonCore

@MainActor
final class DaemonRuntime {
    private let controller = BlockController.makeSystemController()
    private let listener: DaemonListener
    private var powerNotifier: PowerNotifier?
    private var timer: Timer?
    // require several consecutive misses so a transient upgrade gap (rm + cp of the bundle) isn't read as orphaned
    private var orphanMisses = 0
    private let orphanThreshold = 3

    init() {
        listener = DaemonListener(controller: controller)
    }

    func start() {
        listener.start()
        evaluate()
        powerNotifier = PowerNotifier(onWake: { [weak self] in
            DispatchQueue.main.async { self?.evaluate() }
        })
        powerNotifier?.start()
        // 5s keeps the tamper-reassert window tight; hosts/pf self-heal and the agent re-arms within one tick
        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func evaluate() {
        controller.applyDecisionIfNeeded()
        checkOrphan()
    }

    // self-destruct once the owning app is gone and no lock is held — otherwise an uninstalled app
    // leaves a root daemon thrashing forever (KeepAlive can't relaunch it: its binary lives in the deleted bundle)
    private func checkOrphan() {
        guard let bundle = Self.ownAppBundlePath() else { return }
        if controller.isOrphaned(appBundlePath: bundle) {
            orphanMisses += 1
            guard orphanMisses >= orphanThreshold else { return }
            FileHandle.standardError.write(Data("[LockIn] orphaned (app gone, no lock) — self-uninstalling\n".utf8))
            _ = controller.prepareUninstall()
            Self.bootoutSelf()
            exit(0)
        } else {
            orphanMisses = 0
        }
    }

    // <App>.app/Contents/MacOS/lockind → three levels up is the .app bundle
    private static func ownAppBundlePath() -> String? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buf = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return nil }
        let exe = URL(fileURLWithPath: String(cString: buf)).resolvingSymlinksInPath()
        return exe.deletingLastPathComponent().deletingLastPathComponent()
                  .deletingLastPathComponent().path
    }

    private static func bootoutSelf() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "system/com.humblebee.lockin.daemon"]
        try? task.run()
        task.waitUntilExit()
    }
}

FileHandle.standardError.write(Data("[LockIn] lockind starting (pid \(getpid()))\n".utf8))
let runtime = DaemonRuntime()
runtime.start()
FileHandle.standardError.write(Data("[LockIn] lockind listening\n".utf8))
RunLoop.main.run()
