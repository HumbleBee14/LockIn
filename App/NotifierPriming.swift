import AppKit

@MainActor
enum NotifierPriming {
    private static var primed = false

    static func primeOnce() {
        guard !primed else { return }
        let appURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/Helpers/LockInNotifier.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else { return }
        primed = true
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--prime", "1"]
        config.createsNewApplicationInstance = true
        config.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
    }
}
