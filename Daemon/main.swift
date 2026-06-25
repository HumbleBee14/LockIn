import Foundation
import LockInDaemonCore

@MainActor
final class DaemonRuntime {
    private let controller = BlockController.makeSystemController()
    private let listener: DaemonListener
    private var powerNotifier: PowerNotifier?
    private var timer: Timer?

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
        controller.applyDecisionIfNeeded(timeResolved: controller.timeIsResolved())
    }
}

FileHandle.standardError.write(Data("[LockIn] lockind starting (pid \(getpid()))\n".utf8))
let runtime = DaemonRuntime()
runtime.start()
FileHandle.standardError.write(Data("[LockIn] lockind listening\n".utf8))
RunLoop.main.run()
