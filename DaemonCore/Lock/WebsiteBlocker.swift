import Foundation

final class WebsiteBlocker {
    static func expand(_ domain: String) -> [String] {
        let apex = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        return [apex, "www.\(apex)", "m.\(apex)", "api.\(apex)"]
    }

    func apply(domains: [String], allowlist: Bool) {
        let expanded = domains.flatMap { Self.expand($0) }
        let manager = BlockManager(asAllowlist: allowlist, allowLocal: true,
                                   includeCommonSubdomains: true, includeLinkedDomains: false)
        manager?.prepareToAddBlock()
        manager?.addBlockEntries(from: expanded)
        manager?.finalizeBlock()
    }

    func clear() {
        let manager = BlockManager(asAllowlist: false, allowLocal: true,
                                   includeCommonSubdomains: true, includeLinkedDomains: false)
        _ = manager?.clearBlock()
    }

    func isApplied() -> Bool {
        PacketFilter.blockFoundInPF()
    }

    func reassertIfTampered(domains: [String], allowlist: Bool) {
        // re-apply if a tamper removed the block mid-window
        if !isApplied() { apply(domains: domains, allowlist: allowlist) }
    }
}
