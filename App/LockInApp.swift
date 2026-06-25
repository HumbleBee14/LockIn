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
        // single instance: if another copy with our bundle id is already running, focus it and quit
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0 != NSRunningApplication.current }
        if let other = others.first {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }
}
