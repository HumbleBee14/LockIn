import XCTest
@testable import LockInDaemonCore

// records engine-call order without touching /etc/hosts
private final class RecordingBlocker: WebsiteBlocker, @unchecked Sendable {
    let lock = NSLock()
    var events: [String] = []
    var applyDelay: TimeInterval = 0
    private func record(_ e: String) { lock.lock(); events.append(e); lock.unlock() }

    override func apply(domains: [String], allowlist: Bool, expandSubdomains: Bool) -> Bool {
        if applyDelay > 0 { Thread.sleep(forTimeInterval: applyDelay) }
        record("apply:\(domains.sorted().joined(separator: ","))")
        return true
    }
    override func appendToActiveBlock(newDomains: [String], expandSubdomains: Bool) -> Bool {
        record("append:\(newDomains.sorted().joined(separator: ","))")
        return true
    }
}

final class EngineSerializationTests: XCTestCase {
    // T13: applyAndWait must order strictly after an in-flight async apply on the serial queue
    func testApplyAndWaitOrdersAfterInFlightAsyncApply() {
        let b = RecordingBlocker(forceVerified: true)
        b.applyDelay = 0.2
        b.applyAsync(domains: ["a.com"], allowlist: false, expandSubdomains: false)
        b.applyDelay = 0
        let ok = b.applyAndWait(domains: ["a.com", "b.com"], allowlist: false, expandSubdomains: false)
        XCTAssertTrue(ok)
        XCTAssertEqual(b.events, ["apply:a.com", "apply:a.com,b.com"],
                       "sync apply must not interleave with or precede the queued async apply")
    }

    func testApplyAsyncCompletionReportsResult() {
        let b = RecordingBlocker(forceVerified: true)
        let exp = expectation(description: "completion")
        b.applyAsync(domains: ["a.com"], allowlist: false, expandSubdomains: false) { ok in
            XCTAssertTrue(ok); exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testAppendAndWaitRunsOnQueue() {
        let b = RecordingBlocker(forceVerified: true)
        XCTAssertTrue(b.appendAndWait(newDomains: ["c.com"], expandSubdomains: false))
        XCTAssertEqual(b.events, ["append:c.com"])
    }
}
