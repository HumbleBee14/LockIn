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
    var blockSetIds: [String]
    var appBundleIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, weekdays, startHour, startMinute, endHour, endMinute
        case blockSetIds, blockSetId, appBundleIds
    }

    init(id: String, weekdays: [Int], startHour: Int, startMinute: Int,
         endHour: Int, endMinute: Int, blockSetIds: [String], appBundleIds: [String]) {
        self.id = id; self.weekdays = weekdays
        self.startHour = startHour; self.startMinute = startMinute
        self.endHour = endHour; self.endMinute = endMinute
        self.blockSetIds = blockSetIds; self.appBundleIds = appBundleIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        weekdays = try c.decode([Int].self, forKey: .weekdays)
        startHour = try c.decode(Int.self, forKey: .startHour)
        startMinute = try c.decode(Int.self, forKey: .startMinute)
        endHour = try c.decode(Int.self, forKey: .endHour)
        endMinute = try c.decode(Int.self, forKey: .endMinute)
        appBundleIds = (try? c.decode([String].self, forKey: .appBundleIds)) ?? []
        // migrate old single-id configs to the array form
        if let ids = try? c.decode([String].self, forKey: .blockSetIds) {
            blockSetIds = ids
        } else if let single = try? c.decode(String.self, forKey: .blockSetId) {
            blockSetIds = [single]
        } else {
            blockSetIds = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(startHour, forKey: .startHour)
        try c.encode(startMinute, forKey: .startMinute)
        try c.encode(endHour, forKey: .endHour)
        try c.encode(endMinute, forKey: .endMinute)
        try c.encode(blockSetIds, forKey: .blockSetIds)
        try c.encode(appBundleIds, forKey: .appBundleIds)
    }
}

struct SettingsConfig: Codable, Equatable {
    var clockTamperProtection: Bool = true
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
