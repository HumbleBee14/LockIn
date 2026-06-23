import Foundation

enum BlockMode: String, Codable { case scheduled, adHoc }

struct LockState: Codable, Equatable {
    var active: Bool
    var mode: BlockMode
    var windowEnd: Date?
    var duration: Double?
    var anchorWallTime: Date
    var trustedNowAtLastHeartbeat: Date
    var servedElapsedAtLastHeartbeat: Double
    var clockSuspicious: Bool
    var cumulativeDriftSeconds: Double = 0
    var bootSessionUUID: String
    var appliedDomains: [String]
    var appliedAppBundleIds: [String]
    var appliedSettings: SettingsConfig = SettingsConfig()
    var isAllowlist: Bool = false
    var blockSetId: String = ""
    var blockSetTitle: String = ""
    var scheduleRuleId: String?
}

final class LockStateStore {
    private let path: URL
    init(path: URL) { self.path = path }

    func load() -> LockState? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? PropertyListDecoder().decode(LockState.self, from: data)
    }

    func save(_ state: LockState) throws {
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}
