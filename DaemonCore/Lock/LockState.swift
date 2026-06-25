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

struct LockSnapshot: Codable, Equatable {
    var id: String
    var mode: BlockMode
    var windowEnd: Date?
    var duration: Double?
    var isAllowlist: Bool
    var appliedDomains: [String]
    var appliedAppBundleIds: [String]
    var appliedSettings: SettingsConfig
    var blockSetId: String
    var blockSetTitle: String
    var anchorWallTime: Date
    var trustedNowAtLastHeartbeat: Date
    var servedElapsedAtLastHeartbeat: Double
    var clockSuspicious: Bool
    var cumulativeDriftSeconds: Double = 0
    var bootSessionUUID: String
}

final class LockSnapshotStore {
    private let path: URL
    init(path: URL) { self.path = path }

    func load() -> [LockSnapshot] {
        guard let data = try? Data(contentsOf: path) else { return [] }
        if let set = try? PropertyListDecoder().decode([LockSnapshot].self, from: data) { return set }
        // migrate a legacy single-LockState plist so an in-progress lock survives the upgrade
        if let legacy = try? PropertyListDecoder().decode(LockState.self, from: data), legacy.active {
            return [Self.migrate(legacy)]
        }
        return []
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

    private static func migrate(_ s: LockState) -> LockSnapshot {
        LockSnapshot(id: s.scheduleRuleId ?? "quick", mode: s.mode, windowEnd: s.windowEnd,
            duration: s.duration, isAllowlist: s.isAllowlist, appliedDomains: s.appliedDomains,
            appliedAppBundleIds: s.appliedAppBundleIds, appliedSettings: s.appliedSettings,
            blockSetId: s.blockSetId, blockSetTitle: s.blockSetTitle, anchorWallTime: s.anchorWallTime,
            trustedNowAtLastHeartbeat: s.trustedNowAtLastHeartbeat,
            servedElapsedAtLastHeartbeat: s.servedElapsedAtLastHeartbeat,
            clockSuspicious: s.clockSuspicious, cumulativeDriftSeconds: s.cumulativeDriftSeconds,
            bootSessionUUID: s.bootSessionUUID)
    }
}
