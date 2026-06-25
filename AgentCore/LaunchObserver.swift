import Foundation
import AppKit

public final class LaunchObserver {
    private var token: NSObjectProtocol?

    public init() {}

    public func start() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier else { return }
            let iconPath = Self.writeIcon(for: app)
            self.notifyIfBlocked(bundleId: bid, appName: app.localizedName, iconPath: iconPath)
        }
    }

    public func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    private func notifyIfBlocked(bundleId: String, appName: String?, iconPath: String?) {
        fetchStatus { status in
            guard let status, status.active, status.appliedAppBundleIds.contains(bundleId) else { return }
            DispatchQueue.main.async {
                Self.launchNotifier(appName: appName ?? bundleId, endsAt: status.endsAt, iconPath: iconPath)
            }
        }
    }

    private static func writeIcon(for app: NSRunningApplication) -> String? {
        guard let icon = app.icon, let tiff = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let path = NSTemporaryDirectory() + "lockin-blocked-\(UUID().uuidString).png"
        guard (try? png.write(to: URL(fileURLWithPath: path))) != nil else { return nil }
        return path
    }

    private func fetchStatus(_ completion: @escaping (DaemonStatus?) -> Void) {
        let c = NSXPCConnection(machServiceName: XPCRequirements.daemonServiceName)
        c.remoteObjectInterface = NSXPCInterface(with: LockInDaemonProtocol.self)
        c.resume()
        let proxy = c.remoteObjectProxyWithErrorHandler { _ in
            completion(nil); c.invalidate()
        } as? LockInDaemonProtocol
        proxy?.getStatus { data in
            defer { c.invalidate() }
            guard let data, let s = try? JSONDecoder().decode(DaemonStatus.self, from: data) else {
                completion(nil); return
            }
            completion(s)
        }
    }

    private static func launchNotifier(appName: String, endsAt: Date?, iconPath: String?) {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0])
        let helpers = exe.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PlugIns/Helpers/LockInNotifier.app")
        guard FileManager.default.fileExists(atPath: helpers.path) else {
            LockInLog.error("notifier missing at \(helpers.path)")
            return
        }
        var args = ["--name", appName]
        if let endsAt {
            let f = DateFormatter(); f.locale = .current; f.dateFormat = "HH:mm"
            args += ["--ends", f.string(from: endsAt)]
        }
        if let iconPath { args += ["--icon", iconPath] }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = args
        config.activates = false
        NSWorkspace.shared.openApplication(at: helpers, configuration: config) { _, error in
            if let error { LockInLog.error("notifier launch failed", error) }
        }
    }
}
