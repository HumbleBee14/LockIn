import Foundation

public struct BlockedAppSnapshot: Codable, Equatable {
    public var active: Bool
    public var bundleIds: [String]

    public init(active: Bool, bundleIds: [String]) {
        self.active = active
        self.bundleIds = bundleIds
    }
}
