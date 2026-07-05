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
        // Do NOT reset applyDelay here — the queued async apply must still be
        // in flight (sleeping) when applyAndWait is called below. Resetting
        // it before the async block reads it races the delay away and no
        // longer proves that applyAndWait blocks on an in-flight slow apply.
        let start = Date()
        let ok = b.applyAndWait(domains: ["a.com", "b.com"], allowlist: false, expandSubdomains: false)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(ok)
        XCTAssertEqual(b.events, ["apply:a.com", "apply:a.com,b.com"],
                       "sync apply must not interleave with or precede the queued async apply")
        // applyAndWait must have waited out the in-flight async apply (0.2s)
        // plus run its own apply (0.2s, since applyDelay is still 0.2).
        // 0.35 leaves slack for scheduler jitter while still failing if
        // applyAndWait didn't genuinely wait on the in-flight apply.
        XCTAssertGreaterThanOrEqual(elapsed, 0.35,
                       "applyAndWait must block for the full duration of the in-flight apply plus its own apply")
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
