import XCTest
@testable import LockInDaemonCore

final class EffectiveBlockTests: XCTestCase {
    private func s(_ id: String, allow: Bool, domains: [String], apps: [String] = []) -> LockSnapshot {
        LockSnapshot(id: id, mode: .scheduled, windowEnd: Date(timeIntervalSince1970: 1), duration: nil,
            isAllowlist: allow, appliedDomains: domains, appliedAppBundleIds: apps,
            appliedSettings: SettingsConfig(), blockSetId: id, blockSetTitle: id,
            anchorWallTime: Date(timeIntervalSince1970: 0), trustedNowAtLastHeartbeat: Date(timeIntervalSince1970: 0),
            servedElapsedAtLastHeartbeat: 0, clockSuspicious: false, cumulativeDriftSeconds: 0, bootSessionUUID: "B")
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
}
