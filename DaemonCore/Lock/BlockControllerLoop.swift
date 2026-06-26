import Foundation

extension BlockController {
    public func applyDecisionIfNeeded(calendar: Calendar = .current) {
        reconcile(calendar: calendar)
    }
}
