import Foundation

struct Rule: Codable, Equatable {
    var id: String
    var weekdays: [Int]
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var blockSetId: String
    var appBundleIds: [String]
}

struct SettingsConfig: Codable, Equatable {
    var clockTamperProtection: Bool = true
    var blockSettingsPaneWhileActive: Bool = false
    var appBlockingEnabled: Bool = true
}

enum BlockSetMode: String, Codable {
    case blocklist
    case allowlist
}

struct BlockSet: Codable, Equatable {
    var id: String
    var name: String
    var domains: [String]
    var appBundleIds: [String]
    var mode: BlockSetMode = .blocklist
}

struct ScheduleConfig: Codable, Equatable {
    var rules: [Rule]
    var blockSets: [BlockSet] = []
    var settings: SettingsConfig = SettingsConfig()
}
