import SwiftUI
import ServiceManagement
import AppKit

@main
struct LockInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 820, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // single-window app: never restore stale saved window state (it can yield a windowless foreground app)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0 != NSRunningApplication.current && !$0.isTerminated }
        if let other = others.first {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureWindowVisible()
        Task { @MainActor in
            let installer = InstallerService()
            let alive = await DaemonClient().ping()
            installer.reconcileStaleRegistration(daemonAlive: alive)
            installer.registerAgentIfDaemonReady()
        }
    }

    // a windowless foreground app (stale-state restoration yielding no window) is unusable; force one
    private func ensureWindowVisible() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if NSApp.windows.contains(where: { $0.canBecomeMain && !$0.isMiniaturized }) {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            } else {
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { for w in sender.windows { w.makeKeyAndOrderFront(nil) } }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}
