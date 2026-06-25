import Foundation

extension BlockController {
    public func applyDecisionIfNeeded(timeResolved: Bool, calendar: Calendar = .current) {
        // invariant: served-based ad-hoc expiry is clock-tamper-immune and must lift even when time is unresolved
        guard timeResolved else {
            reconcile(calendar: calendar, servedExpiryOnly: true)
            return
        }
        reconcile(calendar: calendar)
    }
}
