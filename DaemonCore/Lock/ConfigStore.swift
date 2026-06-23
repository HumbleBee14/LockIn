import Foundation

final class ConfigStore: Sendable {
    static let shared = ConfigStore(
        path: URL(fileURLWithPath: "/Library/Application Support/LockIn/config.plist"))
    private let path: URL
    init(path: URL) { self.path = path }

    func load() -> ScheduleConfig? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? PropertyListDecoder().decode(ScheduleConfig.self, from: data)
    }

    func save(_ config: ScheduleConfig) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListEncoder().encode(config)
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}
