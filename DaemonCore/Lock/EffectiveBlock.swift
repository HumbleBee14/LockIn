import Foundation

enum EffectiveBlock {
    static func resolve(_ snapshots: [LockSnapshot]) -> (domains: [String], apps: [String], isAllowlist: Bool) {
        guard !snapshots.isEmpty else { return ([], [], false) }
        let apps = dedup(snapshots.flatMap { $0.appliedAppBundleIds })
        let allowlist = snapshots.contains { $0.isAllowlist }
        guard allowlist else {
            return (dedup(snapshots.flatMap { $0.appliedDomains }), apps, false)
        }
        // invariant (Law 3): a blocklisted site stays blocked at the level the engine enforces.
        // both sides use maximal expansion (wwwPair + CDN) so no spelling/expansion re-opens it;
        // over-removal from the allowlist is fail-closed (more restrictive).
        let blocked = Set(snapshots.filter { !$0.isAllowlist }
            .flatMap { $0.appliedDomains }
            .flatMap { WebsiteBlocker.expand($0) })
        let allowed = dedup(snapshots.filter { $0.isAllowlist }.flatMap { $0.appliedDomains })
            .filter { blocked.isDisjoint(with: WebsiteBlocker.expand($0)) }
        return (allowed, apps, true)
    }

    // one deterministic engine flag, stable under expiry/append (spec D2): expansion widens a
    // blocklist (OR over all) but widens reachability for an allowlist (only allowlist flags govern)
    static func effectiveExpand(_ snapshots: [LockSnapshot]) -> Bool {
        let allow = snapshots.filter { $0.isAllowlist }
        let sources = allow.isEmpty ? snapshots : allow
        return sources.contains { $0.appliedSettings.expandSubdomains }
    }

    private static func dedup(_ xs: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for x in xs where seen.insert(x).inserted { out.append(x) }
        return out
    }
}
