import AppKit
import UserNotifications

final class NotifierDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { NSApp.terminate(nil) }
        let args = parseArgs()
        guard let name = args["name"] else { NSApp.terminate(nil); return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { DispatchQueue.main.async { NSApp.terminate(nil) }; return }
            let content = UNMutableNotificationContent()
            content.title = "\(name) is blocked"
            content.body = args["ends"].map { "Blocked by LockIn until \($0)." } ?? "Blocked by LockIn."
            if let icon = args["icon"], FileManager.default.fileExists(atPath: icon),
               let attach = try? UNNotificationAttachment(identifier: "icon",
                                                          url: URL(fileURLWithPath: icon)) {
                content.attachments = [attach]
            }
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { NSApp.terminate(nil) }
            }
        }
    }

    private func parseArgs() -> [String: String] {
        var out: [String: String] = [:]
        let a = CommandLine.arguments
        var i = 1
        while i < a.count {
            if a[i].hasPrefix("--"), i + 1 < a.count {
                out[String(a[i].dropFirst(2))] = a[i + 1]
                i += 2
            } else { i += 1 }
        }
        return out
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = NotifierDelegate()
app.delegate = delegate
app.run()
