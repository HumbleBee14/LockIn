import Foundation

final class WebsiteBlocker {
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

    func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) {
        let entries = Self.entries(for: domains, expand: expandSubdomains)
        let manager = BlockManager(asAllowlist: allowlist, allowLocal: true,
                                   includeCommonSubdomains: true, includeLinkedDomains: false)
        manager?.prepareToAddBlock()
        manager?.addBlockEntries(from: entries)
        manager?.finalizeBlock()
    }

    // incremental: append only the new domains to a running block (no teardown, resolve only these)
    func appendToActiveBlock(newDomains: [String], expandSubdomains: Bool) {
        let entries = Self.entries(for: newDomains, expand: expandSubdomains)
        guard !entries.isEmpty else { return }
        let manager = BlockManager(asAllowlist: false, allowLocal: true,
                                   includeCommonSubdomains: true, includeLinkedDomains: false)
        manager?.enterAppendMode()
        manager?.addBlockEntries(from: entries)
        manager?.finishAppending()
    }

    func clear() {
        let manager = BlockManager(asAllowlist: false, allowLocal: true,
                                   includeCommonSubdomains: true, includeLinkedDomains: false)
        _ = manager?.clearBlock()
    }

    func isApplied() -> Bool {
        PacketFilter.blockFoundInPF()
    }

    func reassertIfTampered(domains: [String], allowlist: Bool, expandSubdomains: Bool) {
        // re-apply if a tamper removed the block mid-window
        if !isApplied() { apply(domains: domains, allowlist: allowlist, expandSubdomains: expandSubdomains) }
    }
}
