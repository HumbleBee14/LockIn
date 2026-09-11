import XCTest
@testable import LockIn

final class ScheduleWindowTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: h, minute: m))!
    }

    func testRuleCarriesWindowFieldsAndSortsWeekdays() {
        let w = ScheduleWindow(weekdays: [5, 1, 3], start: date(9, 30), end: date(17, 45))
        let rule = w.rule(id: "r", blockSetIds: ["social"], calendar: cal)
        XCTAssertEqual(rule.id, "r")
        XCTAssertEqual(rule.weekdays, [1, 3, 5])
        XCTAssertEqual(rule.startHour, 9); XCTAssertEqual(rule.startMinute, 30)
        XCTAssertEqual(rule.endHour, 17); XCTAssertEqual(rule.endMinute, 45)
        XCTAssertEqual(rule.blockSetIds, ["social"])
        XCTAssertEqual(rule.appBundleIds, [])
    }

    func testInitFromRuleRoundTrips() {
        let rule = Rule(id: "r", weekdays: [2, 4], startHour: 22, startMinute: 15, endHour: 6, endMinute: 0,
                        blockSetIds: ["a"], appBundleIds: [])
        let w = ScheduleWindow(rule: rule, calendar: cal, now: date(12, 0))
        XCTAssertEqual(w.weekdays, [2, 4])
        XCTAssertEqual(w.rule(id: "r", blockSetIds: ["a"], calendar: cal), rule)
    }

    func testUpcomingStartsAtNextFullHourForOneHourEveryDay() {
        let w = ScheduleWindow.upcoming(now: date(13, 20), calendar: cal)
        XCTAssertEqual(w.weekdays, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(w.start, date(14, 0))
        XCTAssertEqual(w.end, date(15, 0))
        XCTAssertTrue(w.isValid)
    }

    func testEmptyWeekdaysIsInvalid() {
        let w = ScheduleWindow(weekdays: [], start: date(9, 0), end: date(10, 0))
        XCTAssertFalse(w.isValid)
    }

    func testSummaryNamesCommonDayGroups() {
        let s = date(9, 0), e = date(17, 30)
        XCTAssertEqual(ScheduleWindow(weekdays: [1, 2, 3, 4, 5, 6, 7], start: s, end: e).summary(calendar: cal),
                       "Every day 09:00–17:30")
        XCTAssertEqual(ScheduleWindow(weekdays: [1, 2, 3, 4, 5], start: s, end: e).summary(calendar: cal),
                       "Weekdays 09:00–17:30")
        XCTAssertEqual(ScheduleWindow(weekdays: [6, 7], start: s, end: e).summary(calendar: cal),
                       "Weekends 09:00–17:30")
        XCTAssertEqual(ScheduleWindow(weekdays: [1, 3, 5], start: s, end: e).summary(calendar: cal),
                       "Mon, Wed, Fri 09:00–17:30")
    }
}
