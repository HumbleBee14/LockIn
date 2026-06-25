import Foundation

enum ConfigPersistence {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LockIn/config.json")
    }

    static func load() -> ScheduleConfig? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ScheduleConfig.self, from: data)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func save(_ config: ScheduleConfig) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
