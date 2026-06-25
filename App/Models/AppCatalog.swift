import Foundation
import AppKit

struct AppInfo: Identifiable, Equatable {
    let bundleId: String
    let name: String
    var id: String { bundleId }
}

enum AppCatalog {
    static let searchPaths = ["/Applications", "/System/Applications"]

    static func installedAndRunning() -> [AppInfo] {
        merge(installed: scanInstalled(), running: scanRunning())
    }

    // pure core, unit-testable without touching the filesystem or NSWorkspace
    static func merge(installed: [AppInfo], running: [AppInfo]) -> [AppInfo] {
        let ownBundleId = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var out: [AppInfo] = []
        for app in installed + running {
            guard !app.bundleId.isEmpty, app.bundleId != ownBundleId else { continue }
            if seen.insert(app.bundleId).inserted { out.append(app) }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func icon(forBundleId id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func scanInstalled() -> [AppInfo] {
        var apps: [AppInfo] = []
        for path in searchPaths {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            for entry in entries where entry.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: path).appendingPathComponent(entry)
                guard let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier else { continue }
                apps.append(AppInfo(bundleId: id, name: displayName(bundle: bundle, fallback: entry)))
            }
        }
        return apps
    }

    private static func scanRunning() -> [AppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return nil }
            return AppInfo(bundleId: id, name: app.localizedName ?? id)
        }
    }

    private static func displayName(bundle: Bundle, fallback: String) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallback.replacingOccurrences(of: ".app", with: "")
    }
}
