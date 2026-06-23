import Foundation

struct Decision: Equatable {
    let shouldBlock: Bool
    let activeRule: Rule?
    let windowEnd: Date?
}

enum Scheduler {
    static func evaluate(_ config: ScheduleConfig, at trustedNow: Date, calendar: Calendar) -> Decision {
        for rule in config.rules {
            if let end = activeWindowEnd(rule, at: trustedNow, calendar: calendar) {
                return Decision(shouldBlock: true, activeRule: rule, windowEnd: end)
            }
        }
        return Decision(shouldBlock: false, activeRule: nil, windowEnd: nil)
    }

    private static func activeWindowEnd(_ rule: Rule, at now: Date, calendar: Calendar) -> Date? {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        guard let hour = comps.hour, let minute = comps.minute, let wd = comps.weekday else { return nil }
        let weekdayMon1 = ((wd + 5) % 7) + 1
        let nowMin = hour * 60 + minute
        let startMin = rule.startHour * 60 + rule.startMinute
        let endMin = rule.endHour * 60 + rule.endMinute
        let crossesMidnight = startMin > endMin

        let inToday: Bool
        let prevDayTail: Bool
        if crossesMidnight {
            inToday = nowMin >= startMin
            prevDayTail = nowMin < endMin
        } else {
            inToday = nowMin >= startMin && nowMin < endMin
            prevDayTail = false
        }

        if inToday, rule.weekdays.contains(weekdayMon1) {
            return windowEndDate(now: now, endMin: endMin, calendar: calendar)
        }
        if prevDayTail {
            let prevWd = ((weekdayMon1 - 2 + 7) % 7) + 1
            if rule.weekdays.contains(prevWd) {
                return windowEndDate(now: now, endMin: endMin, calendar: calendar)
            }
        }
        return nil
    }

    private static func windowEndDate(now: Date, endMin: Int, calendar: Calendar) -> Date? {
        let dayStart = calendar.startOfDay(for: now)
        let candidate = calendar.date(byAdding: .minute, value: endMin, to: dayStart)!
        if candidate > now { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate)
    }
}
