import Foundation

enum EffectiveBlock {
    static func resolve(_ snapshots: [LockSnapshot]) -> (domains: [String], apps: [String], isAllowlist: Bool) {
        guard !snapshots.isEmpty else { return ([], [], false) }
        // allowlist-wins: any active allowlist makes the whole state allowlist (most restrictive)
        let allowlist = snapshots.contains { $0.isAllowlist }
        let domainSources = allowlist ? snapshots.filter { $0.isAllowlist } : snapshots
        return (dedup(domainSources.flatMap { $0.appliedDomains }),
                dedup(snapshots.flatMap { $0.appliedAppBundleIds }),
                allowlist)
    }

    private static func dedup(_ xs: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for x in xs where seen.insert(x).inserted { out.append(x) }
        return out
    }
}
