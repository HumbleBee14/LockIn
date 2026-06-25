import Foundation

enum BlockLimits {
    static let maxActiveDomains = 100_000   // cap on stored/added domains per active block
    static let maxHostsEntries = 150_000    // hard ceiling on lines written to /etc/hosts
}

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
    var expandSubdomains: Bool = false
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
