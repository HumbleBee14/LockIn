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
}
