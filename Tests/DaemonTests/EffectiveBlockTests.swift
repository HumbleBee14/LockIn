import XCTest
@testable import LockInDaemonCore

final class EffectiveBlockTests: XCTestCase {
    private func s(_ id: String, allow: Bool, domains: [String], apps: [String] = []) -> LockSnapshot {
        LockSnapshot(id: id, mode: .scheduled, endsAt: Date(timeIntervalSince1970: 1),
            isAllowlist: allow, appliedDomains: domains, appliedAppBundleIds: apps,
            appliedSettings: SettingsConfig(), blockSetId: id, blockSetTitle: id)
    }

    func testEmpty() {
        let r = EffectiveBlock.resolve([])
        XCTAssertEqual(r.domains, []); XCTAssertFalse(r.isAllowlist)
    }

    func testTwoBlocklistsUnion() {
        let r = EffectiveBlock.resolve([s("a", allow: false, domains: ["x.com", "y.com"]),
                                        s("b", allow: false, domains: ["y.com", "z.com"])])
        XCTAssertEqual(Set(r.domains), ["x.com", "y.com", "z.com"])
        XCTAssertFalse(r.isAllowlist)
    }

    func testAllowlistWinsOnMixedOverlap() {
        let r = EffectiveBlock.resolve([s("block", allow: false, domains: ["adult.com"]),
                                        s("allow", allow: true, domains: ["gmail.com"])])
        XCTAssertTrue(r.isAllowlist, "any active allowlist makes the effective mode allowlist")
        XCTAssertEqual(Set(r.domains), ["gmail.com"], "only the allowlist set defines what's reachable")
    }

    func testAppsUnionAcrossAll() {
        let r = EffectiveBlock.resolve([s("a", allow: false, domains: ["x.com"], apps: ["com.A"]),
                                        s("b", allow: false, domains: ["y.com"], apps: ["com.B"])])
        XCTAssertEqual(Set(r.apps), ["com.A", "com.B"])
    }

    private func snap(_ id: String, allow: Bool, domains: [String], expand: Bool = false,
                      ends: TimeInterval = 1000) -> LockSnapshot {
        var settings = SettingsConfig()
        settings.expandSubdomains = expand
        return LockSnapshot(id: id, mode: .adHoc, endsAt: Date(timeIntervalSince1970: ends),
                            isAllowlist: allow, appliedDomains: domains, appliedAppBundleIds: [],
                            appliedSettings: settings, blockSetId: id, blockSetTitle: id)
    }

    // T4: the www/apex bypass — blocklist youtube.com + allowlist www.youtube.com must not pass either host
    func testAllowlistSubtractionIsExpansionAware() {
        let e = EffectiveBlock.resolve([snap("b", allow: false, domains: ["youtube.com"]),
                                        snap("a", allow: true, domains: ["www.youtube.com", "gmail.com"])])
        XCTAssertTrue(e.isAllowlist)
        XCTAssertEqual(e.domains, ["gmail.com"], "www.youtube.com expands to the blocked apex; must be dropped")
    }

    func testAllowlistSubtractionCatchesNumberedCDN() {
        let e = EffectiveBlock.resolve([snap("b", allow: false, domains: ["cdn3.host.com"]),
                                        snap("a", allow: true, domains: ["cdn7.host.com"])])
        XCTAssertEqual(e.domains, [], "numbered-CDN expansions overlap; allow entry must be dropped")
    }

    func testAllowlistSubtractionCanEmpty() {
        let e = EffectiveBlock.resolve([snap("b", allow: false, domains: ["gmail.com"]),
                                        snap("a", allow: true, domains: ["www.gmail.com"])])
        XCTAssertEqual(e.domains, [], "an emptied allowlist is maximally restrictive — allowed by Law 3")
        XCTAssertTrue(e.isAllowlist)
    }

    // T12 (policy half): OR over all in blocklist mode; OR over allowlist snapshots when mixed
    func testEffectiveExpandPolicy() {
        XCTAssertTrue(EffectiveBlock.effectiveExpand([snap("1", allow: false, domains: ["x.com"], expand: false),
                                                      snap("2", allow: false, domains: ["y.com"], expand: true)]))
        XCTAssertFalse(EffectiveBlock.effectiveExpand([snap("1", allow: false, domains: ["x.com"], expand: true),
                                                       snap("a", allow: true, domains: ["g.com"], expand: false)]),
                       "mixed mode: only allowlist snapshots' flags govern reachable expansion")
        XCTAssertFalse(EffectiveBlock.effectiveExpand([]))
    }
}
