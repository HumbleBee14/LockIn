import Foundation
import ServiceManagement
import LockInDaemonCore

@MainActor
final class DaemonRuntime {
    private let controller = BlockController.makeSystemController()
    private let listener: DaemonListener
    private var powerNotifier: PowerNotifier?
    private var timer: Timer?

    // .../LockIn.app/Contents/MacOS/lockind -> .../LockIn.app
    private let appBundlePath = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path

    init() {
        listener = DaemonListener(controller: controller)
    }

    func start() {
        selfCleanIfOrphaned()
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

    private var ticksSinceOrphanCheck = 0

    private func evaluate() {
        controller.applyDecisionIfNeeded(timeResolved: controller.timeIsResolved())
        ticksSinceOrphanCheck += 1
        if ticksSinceOrphanCheck >= 720 { ticksSinceOrphanCheck = 0; selfCleanIfOrphaned() }
    }

    private func selfCleanIfOrphaned() {
        guard controller.isOrphaned(appBundlePath: appBundlePath) else { return }
        _ = controller.prepareUninstall()
        try? SMAppService.daemon(plistName: "lockind.plist").unregister()
        exit(0)
    }
}

let runtime = DaemonRuntime()
runtime.start()
FileHandle.standardError.write(Data("lockind listening\n".utf8))
RunLoop.main.run()
