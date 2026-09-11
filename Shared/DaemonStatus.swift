import Foundation

public struct ActiveLockInfo: Codable, Equatable, Sendable {
    public let id: String
    public let title: String          // that snapshot's blockSetTitle
    public let source: String         // "quick" | "scheduled"
    public let endsAt: Date
    public let isAllowlist: Bool
    public let blockSetId: String
    public let domainCount: Int       // that snapshot's frozen domain count

    public init(id: String, title: String, source: String, endsAt: Date,
                isAllowlist: Bool, blockSetId: String, domainCount: Int) {
        self.id = id; self.title = title; self.source = source; self.endsAt = endsAt
        self.isAllowlist = isAllowlist; self.blockSetId = blockSetId; self.domainCount = domainCount
    }
}

public struct DaemonStatus: Codable, Equatable, Sendable {
    public let active: Bool
    public let source: String?          // "quick" | "scheduled"
    public let blockSetId: String?
    public let blockSetTitle: String?
    public let isAllowlist: Bool
    public let endsAt: Date?            // absolute end for the countdown (both modes)
    public let appliedDomains: [String]
    public let appliedAppBundleIds: [String]
    public let nextTriggerDescription: String?
    public let pfApplied: Bool          // firewall layer live too (hosts is proven by the lock existing)
    public let cleanupFailed: Bool      // a teardown couldn't fully clear hosts/pf — prompt the user to Reset
    public let locks: [ActiveLockInfo]?          // per-lock detail; nil from old daemons
    public let appendTargetBlockSetId: String?   // set the lock-screen "add a site" persists into
    public let engineDegraded: Bool?             // a live-lock engine write keeps failing (over-block direction)
    public let skippedScheduleTitles: [String]?  // due rules the tick could not arm without exceeding the union cap

    public init(active: Bool, source: String?, blockSetId: String? = nil, blockSetTitle: String?, isAllowlist: Bool,
                endsAt: Date?, appliedDomains: [String], appliedAppBundleIds: [String] = [],
                nextTriggerDescription: String?, pfApplied: Bool = false, cleanupFailed: Bool = false,
                locks: [ActiveLockInfo]? = nil, appendTargetBlockSetId: String? = nil, engineDegraded: Bool? = nil,
                skippedScheduleTitles: [String]? = nil) {
        self.active = active
        self.source = source
        self.blockSetId = blockSetId
        self.blockSetTitle = blockSetTitle
        self.isAllowlist = isAllowlist
        self.endsAt = endsAt
        self.appliedDomains = appliedDomains
        self.appliedAppBundleIds = appliedAppBundleIds
        self.nextTriggerDescription = nextTriggerDescription
        self.pfApplied = pfApplied
        self.cleanupFailed = cleanupFailed
        self.locks = locks
        self.appendTargetBlockSetId = appendTargetBlockSetId
        self.engineDegraded = engineDegraded
        self.skippedScheduleTitles = skippedScheduleTitles
    }
}
