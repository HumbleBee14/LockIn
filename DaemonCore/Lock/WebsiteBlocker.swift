import Foundation

class WebsiteBlocker {
    // forces apply() to report success in tests, which can't write /etc/hosts or enable pf
    private let forceVerified: Bool

    init(forceVerified: Bool = false) {
        self.forceVerified = forceVerified
    }

    static func expand(_ domain: String) -> [String] {
        let apex = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        if let numbered = enumerateNumberedPrefix(apex) { return numbered }
        // pair www.↔apex only for bare apex domains; leave already-subdomained hosts as-is
        return apex.split(separator: ".").count == 2 ? [apex, "www.\(apex)"] : [apex]
    }

    // cdn9.host.com → cdn1..cdn10.host.com (a numbered first label implies sibling hosts)
    static func enumerateNumberedPrefix(_ host: String) -> [String]? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2, let first = labels.first else { return nil }
        let trailingDigits = first.reversed().prefix(while: { $0.isNumber }).count
        guard trailingDigits > 0 else { return nil }
        let base = String(first.dropLast(trailingDigits))
        guard !base.isEmpty else { return nil }
        let rest = labels.dropFirst().joined(separator: ".")
        return (1...10).map { "\(base)\($0).\(rest)" }
    }

    static func entries(for domains: [String], expand: Bool) -> [String] {
        let raw = expand ? domains.flatMap { Self.expand($0) } : domains
        // hard ceiling on actual /etc/hosts lines — too many can hang mDNSResponder
        return raw.count > BlockLimits.maxHostsEntries
            ? Array(raw.prefix(BlockLimits.maxHostsEntries)) : raw
    }

    @discardableResult
    func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        let entries = Self.entries(for: domains, expand: expandSubdomains)
        // one user switch governs all expansion: the engine's www./site pairing was previously forced on
        let manager = BlockManager(asAllowlist: allowlist, allowLocal: true,
                                   includeCommonSubdomains: expandSubdomains, includeLinkedDomains: false)
        manager?.prepareToAddBlock()
        manager?.addBlockEntries(from: entries)
        manager?.finalizeBlock()
        if forceVerified { return true }
        // invariant: blocklist must land in /etc/hosts; allowlist holds only if pfctl -E actually enabled pf
        return allowlist ? (manager?.pfDidEnable ?? false) : Self.hostsBlockApplied(entries: entries)
    }

    static func hostsBlockApplied(entries: [String]) -> Bool {
        guard let contents = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return false }
        return blockPresent(in: contents, entries: entries)
    }

    // invariant: markers alone don't count; a real entry must sit inside the block section
    static func blockPresent(in contents: String, entries: [String]) -> Bool {
        let header = "# BEGIN SELFCONTROL BLOCK"
        let footer = "# END SELFCONTROL BLOCK"
        guard !entries.isEmpty,
              let headerRange = contents.range(of: header),
              let footerRange = contents.range(of: footer, range: headerRange.upperBound..<contents.endIndex)
        else { return false }
        let section = contents[headerRange.upperBound..<footerRange.lowerBound]
        return entries.contains { section.contains($0) }
    }

    // incremental: append only the new domains to a running block (no teardown, resolve only these)
    @discardableResult
    func appendToActiveBlock(newDomains: [String], expandSubdomains: Bool) -> Bool {
        let entries = Self.entries(for: newDomains, expand: expandSubdomains)
        guard !entries.isEmpty else { return false }
        let manager = BlockManager(asAllowlist: false, allowLocal: true,
                                   includeCommonSubdomains: expandSubdomains, includeLinkedDomains: false)
        manager?.enterAppendMode()
        manager?.addBlockEntries(from: entries)
        manager?.finishAppending()
        if forceVerified { return true }
        // invariant: confirm the new entries actually landed in /etc/hosts before reporting success
        return Self.hostsBlockApplied(entries: entries)
    }

    func clear() {
        let manager = BlockManager(asAllowlist: false, allowLocal: true,
                                   includeCommonSubdomains: true, includeLinkedDomains: false)
        _ = manager?.clearBlock()
    }

    func resetToSystemDefault() -> Bool {
        let manager = BlockManager(asAllowlist: false, allowLocal: true,
                                   includeCommonSubdomains: true, includeLinkedDomains: false)
        return manager?.resetHostsToDefault() ?? false
    }

    func isApplied() -> Bool {
        PacketFilter.blockFoundInPF()
    }

    // invariant: detects a live block independent of the state file, so deleting active.plist can't fake "unlocked"
    func liveBlockPresent() -> Bool {
        if PacketFilter.blockFoundInPF() { return true }
        guard let contents = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return false }
        let header = "# BEGIN SELFCONTROL BLOCK"
        let footer = "# END SELFCONTROL BLOCK"
        guard let h = contents.range(of: header),
              let f = contents.range(of: footer, range: h.upperBound..<contents.endIndex) else { return false }
        return contents[h.upperBound..<f.lowerBound].contains("0.0.0.0")
    }

    func reassertIfTampered(domains: [String], allowlist: Bool, expandSubdomains: Bool) {
        // re-apply if a tamper removed the block from EITHER pf or the hosts file mid-window
        let entries = Self.entries(for: domains, expand: expandSubdomains)
        let hostsIntact = allowlist || Self.hostsBlockApplied(entries: entries)
        if !isApplied() || !hostsIntact {
            apply(domains: domains, allowlist: allowlist, expandSubdomains: expandSubdomains)
        }
    }
}
