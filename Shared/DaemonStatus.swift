import Foundation

public struct DaemonStatus: Codable, Equatable, Sendable {
    public let active: Bool
    public let source: String?          // "quick" | "scheduled"
    public let blockSetId: String?
    public let blockSetTitle: String?
    public let isAllowlist: Bool
    public let endsAt: Date?            // absolute end for the countdown (both modes)
    public let appliedDomains: [String]
    public let nextTriggerDescription: String?

    public init(active: Bool, source: String?, blockSetId: String? = nil, blockSetTitle: String?, isAllowlist: Bool,
                endsAt: Date?, appliedDomains: [String], nextTriggerDescription: String?) {
        self.active = active
        self.source = source
        self.blockSetId = blockSetId
        self.blockSetTitle = blockSetTitle
        self.isAllowlist = isAllowlist
        self.endsAt = endsAt
        self.appliedDomains = appliedDomains
        self.nextTriggerDescription = nextTriggerDescription
    }
}
