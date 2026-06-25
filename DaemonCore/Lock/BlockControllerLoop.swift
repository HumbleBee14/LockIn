import Foundation

extension BlockController {
    public func applyDecisionIfNeeded(timeResolved: Bool, calendar: Calendar = .current) {
        // never tear down or transition without a resolved time source
        guard timeResolved else { return }
        reconcile(calendar: calendar)
    }
}
