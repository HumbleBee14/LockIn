import Foundation

public struct DaemonStatus: Codable, Equatable {
    public let active: Bool
    public let mode: String?
    public let windowEnd: Date?
    public let appliedDomains: [String]
    public let nextTriggerDescription: String?

    public init(active: Bool, mode: String?, windowEnd: Date?, appliedDomains: [String],
                nextTriggerDescription: String?) {
        self.active = active
        self.mode = mode
        self.windowEnd = windowEnd
        self.appliedDomains = appliedDomains
        self.nextTriggerDescription = nextTriggerDescription
    }
}
