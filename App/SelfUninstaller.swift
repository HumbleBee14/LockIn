import Foundation
import AppKit

enum SelfUninstaller {
    static func canSelfDelete() -> Bool {
        FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.path)
    }

    // spawns a detached script that outlives the app, then deletes the bundle and itself
    @MainActor
    static func selfDeleteAndQuit() {
        let bundle = Bundle.main.bundleURL.path
        let script = NSTemporaryDirectory() + "lockin-uninstall.sh"
        let body = """
        #!/bin/sh
        sleep 2
        rm -rf \(shellQuote(bundle))
        rm -- "$0"
        """
        guard (try? body.write(toFile: script, atomically: true, encoding: .utf8)) != nil else {
            NSApp.terminate(nil); return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [script]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
