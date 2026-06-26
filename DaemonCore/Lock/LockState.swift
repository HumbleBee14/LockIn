import Foundation

enum BlockMode: String, Codable { case scheduled, adHoc }

// expiry is simply: now (online-or-system UTC) >= endsAt. Date is absolute UTC, so sleep/reboot/timezone don't matter.
struct LockSnapshot: Codable, Equatable {
    var id: String
    var mode: BlockMode            // UI label only ("Scheduled" vs "Quick")
    var endsAt: Date
    var isAllowlist: Bool
    var appliedDomains: [String]
    var appliedAppBundleIds: [String]
    var appliedSettings: SettingsConfig
    var blockSetId: String
    var blockSetTitle: String
}

final class LockSnapshotStore {
    private let path: URL
    init(path: URL) { self.path = path }

    func load() -> [LockSnapshot] {
        guard let data = try? Data(contentsOf: path) else { return [] }
        return (try? PropertyListDecoder().decode([LockSnapshot].self, from: data)) ?? []
    }

    func save(_ snapshots: [LockSnapshot]) throws {
        let data = try PropertyListEncoder().encode(snapshots)
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}
