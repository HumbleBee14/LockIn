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
        let t = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func evaluate() {
        controller.applyDecisionIfNeeded(timeResolved: controller.timeIsResolved())
    }
}

let runtime = DaemonRuntime()
runtime.start()
FileHandle.standardError.write(Data("lockind listening\n".utf8))
RunLoop.main.run()
