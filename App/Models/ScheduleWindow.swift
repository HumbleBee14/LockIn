import Foundation

// the "when" of a schedule rule as the editor works with it: picked weekdays plus wall-clock start/end.
// shared by the rule editor and the lock-screen stack sheet so both build the exact same Rule.
struct ScheduleWindow: Equatable {
    var weekdays: Set<Int>   // 1 = Monday … 7 = Sunday, matching Rule.weekdays
    var start: Date          // only hour/minute are meaningful
    var end: Date

    static let allWeekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    private static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(weekdays: Set<Int>, start: Date, end: Date) {
        self.weekdays = weekdays; self.start = start; self.end = end
    }

    init(rule: Rule, calendar: Calendar = .current, now: Date = Date()) {
        weekdays = Set(rule.weekdays)
        start = calendar.date(bySettingHour: rule.startHour, minute: rule.startMinute, second: 0, of: now) ?? now
        end = calendar.date(bySettingHour: rule.endHour, minute: rule.endMinute, second: 0, of: now) ?? now
    }

    // default for a new rule: every day, from the next full hour, one hour long
    static func upcoming(now: Date = Date(), calendar: Calendar = .current) -> ScheduleWindow {
        let thisHour = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: thisHour) ?? now
        let end = calendar.date(byAdding: .hour, value: 1, to: nextHour) ?? nextHour
        return ScheduleWindow(weekdays: allWeekdays, start: nextHour, end: end)
    }

    var isValid: Bool { !weekdays.isEmpty }

    func rule(id: String, blockSetIds: [String], calendar: Calendar = .current) -> Rule {
        let sc = calendar.dateComponents([.hour, .minute], from: start)
        let ec = calendar.dateComponents([.hour, .minute], from: end)
        return Rule(id: id, weekdays: weekdays.sorted(),
                    startHour: sc.hour ?? 22, startMinute: sc.minute ?? 0,
                    endHour: ec.hour ?? 7, endMinute: ec.minute ?? 0,
                    blockSetIds: blockSetIds, appBundleIds: [])
    }

    // "Weekdays 09:00–17:30" — the confirmation shown after saving from the lock screen
    func summary(calendar: Calendar = .current) -> String {
        let sc = calendar.dateComponents([.hour, .minute], from: start)
        let ec = calendar.dateComponents([.hour, .minute], from: end)
        let time = String(format: "%02d:%02d–%02d:%02d", sc.hour ?? 0, sc.minute ?? 0, ec.hour ?? 0, ec.minute ?? 0)
        return "\(dayLabel) \(time)"
    }

    private var dayLabel: String {
        switch weekdays {
        case Self.allWeekdays: return "Every day"
        case [1, 2, 3, 4, 5]: return "Weekdays"
        case [6, 7]: return "Weekends"
        default: return weekdays.sorted().map { Self.shortNames[$0 - 1] }.joined(separator: ", ")
        }
    }
}
