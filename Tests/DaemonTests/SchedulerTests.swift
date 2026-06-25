import XCTest
@testable import LockInDaemonCore

final class SchedulerTests: XCTestCase {
    func testRuleDecodesFromJSON() throws {
        let json = """
        {"id":"nightly","weekdays":[1,2,3,4,5,6,7],"startHour":22,"startMinute":0,
         "endHour":7,"endMinute":0,"blockSetId":"social","appBundleIds":[]}
        """.data(using: .utf8)!
        let rule = try JSONDecoder().decode(Rule.self, from: json)
        XCTAssertEqual(rule.startHour, 22)
        XCTAssertEqual(rule.weekdays.count, 7)
    }

    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); return f.date(from: iso)!
    }
    private var nightly: ScheduleConfig {
        ScheduleConfig(rules: [Rule(id: "n", weekdays: [1, 2, 3, 4, 5, 6, 7],
            startHour: 22, startMinute: 0, endHour: 7, endMinute: 0,
            blockSetIds: ["social"], appBundleIds: [])])
    }
    func testInsideWindowBeforeMidnight() {
        let d = Scheduler.evaluate(nightly, at: date("2026-06-22T23:30:00Z"), calendar: cal())
        XCTAssertTrue(d.shouldBlock)
    }
    func testInsideWindowAfterMidnight() {
        let d = Scheduler.evaluate(nightly, at: date("2026-06-23T03:00:00Z"), calendar: cal())
        XCTAssertTrue(d.shouldBlock)
    }
    func testOutsideWindowMidday() {
        let d = Scheduler.evaluate(nightly, at: date("2026-06-22T12:00:00Z"), calendar: cal())
        XCTAssertFalse(d.shouldBlock)
    }
    func testWindowEndComputedAcrossMidnight() {
        let d = Scheduler.evaluate(nightly, at: date("2026-06-22T23:30:00Z"), calendar: cal())
        XCTAssertEqual(d.windowEnd, date("2026-06-23T07:00:00Z"))
    }
}
