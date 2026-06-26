import AppKit
import UserNotifications

final class NotifierDelegate: NSObject, NSApplicationDelegate {
    private let safetyTimeout: TimeInterval = 30.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + safetyTimeout) { NSApp.terminate(nil) }
        Self.run(args: Self.parseArgs())
    }

    nonisolated private static func run(args: [String: String]) {
        let center = UNUserNotificationCenter.current()
        if args["prime"] != nil {
            center.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in
                quit()
            }
            return
        }
        guard let name = args["name"] else { quit(); return }
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable granted, _ in
            guard granted else { quit(); return }
            let content = UNMutableNotificationContent()
            content.title = "\(name) is blocked"
            content.body = args["ends"].map { "Blocked by LockIn until \($0)." } ?? "Blocked by LockIn."
            if let icon = args["icon"], FileManager.default.fileExists(atPath: icon),
               let attach = try? UNNotificationAttachment(identifier: "icon",
                                                          url: URL(fileURLWithPath: icon)) {
                content.attachments = [attach]
            }
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req) { @Sendable _ in quit(after: 1.0) }
        }
    }

    nonisolated private static func quit(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { NSApp.terminate(nil) }
    }

    nonisolated private static func parseArgs() -> [String: String] {
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
app.setActivationPolicy(.accessory)
let delegate = NotifierDelegate()
app.delegate = delegate
app.run()
