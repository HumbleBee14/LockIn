import Foundation

class WebsiteBlocker {
    // forces apply() to report success in tests, which can't write /etc/hosts or enable pf
    private let forceVerified: Bool

    init(forceVerified: Bool = false) {
        self.forceVerified = forceVerified
    }

    // www.↔apex pairing for bare two-label domains (youtube.com↔www.youtube.com); multi-label hosts unchanged
    static func wwwPair(_ domain: String) -> [String] {
        if domain.hasPrefix("www.") {
            let apex = String(domain.dropFirst(4))
            return apex.split(separator: ".").count == 2 ? [apex, domain] : [domain]
        }
        return domain.split(separator: ".").count == 2 ? [domain, "www.\(domain)"] : [domain]
    }

    // toggle-gated: numbered-CDN enumeration on top of www pairing
    static func expand(_ domain: String) -> [String] {
        let apex = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        if let numbered = enumerateNumberedPrefix(apex) { return numbered }
        return wwwPair(domain)
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
        let raw = domains.flatMap { expand ? Self.expand($0) : Self.wwwPair($0) }
        var seen = Set<String>(); var out: [String] = []
        for d in raw where seen.insert(d).inserted { out.append(d) }
        // cap /etc/hosts lines — too many can hang mDNSResponder
        return out.count > BlockLimits.maxHostsEntries ? Array(out.prefix(BlockLimits.maxHostsEntries)) : out
    }

    @discardableResult
    func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        let entries = Self.entries(for: domains, expand: expandSubdomains)
        let manager = BlockManager(asAllowlist: allowlist, allowLocal: true,
                                   includeCommonSubdomains: false, includeLinkedDomains: false)
        manager?.prepareToAddBlock()
        manager?.addBlockEntries(from: entries)
        manager?.finalizeBlock()
        if forceVerified { return true }
        // invariant: blocklist must land in /etc/hosts; allowlist holds only if pfctl -E actually enabled pf
        if allowlist {
            let ok = manager?.pfDidEnable ?? false
            if !ok { LockInLog.error("apply: allowlist pf did not enable (\(entries.count) entries)") }
            return ok
        }
        let ok = Self.hostsBlockApplied(entries: entries)
        if !ok { LockInLog.error("apply: hosts verify failed for \(entries.count) entries — block not present in /etc/hosts") }
        return ok
    }

    static func hostsBlockApplied(entries: [String]) -> Bool {
        guard let contents = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else {
            LockInLog.error("hosts verify: /etc/hosts unreadable")
            return false
        }
        let present = blockPresent(in: contents, entries: entries)
        if !present {
            let hasMarkers = contents.contains("# BEGIN SELFCONTROL BLOCK")
            LockInLog.error("hosts verify: block-not-present (markers=\(hasMarkers), hostsLines=\(contents.split(separator: "\n").count))")
        }
        return present
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
                                   includeCommonSubdomains: false, includeLinkedDomains: false)
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

    // tick integrity check: catches partial tamper liveBlockPresent() misses, without diffing every entry
    func blockIntact(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        if allowlist { return isApplied() }
        let entries = Self.entries(for: domains, expand: expandSubdomains)
        guard !entries.isEmpty else { return true }
        guard let contents = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return false }
        return Self.sectionIntact(in: contents, entries: entries)
    }

    static func sectionIntact(in contents: String, entries: [String]) -> Bool {
        let header = "# BEGIN SELFCONTROL BLOCK"
        let footer = "# END SELFCONTROL BLOCK"
        guard let h = contents.range(of: header),
              let f = contents.range(of: footer, range: h.upperBound..<contents.endIndex) else { return false }
        let section = contents[h.upperBound..<f.lowerBound]
        if section.components(separatedBy: "0.0.0.0").count - 1 < entries.count { return false }
        let probes = [entries.first, entries[entries.count / 2], entries.last].compactMap { $0 }
        return probes.allSatisfy { section.contains($0) }
    }
}
