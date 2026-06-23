import Foundation

extension BlockController {
    public func applyDecisionIfNeeded(timeResolved: Bool, calendar: Calendar = .current) {
        if let state = loadState(), state.active {
            // never tear down without a resolved time source
            guard timeResolved else { return }
            let beat = guardHeartbeat(state)
            saveState(beat)
            if guardIsExpired(beat) {
                clearBlocking()
                clearState()
                pushClearedSnapshot()
                applyScheduledStartIfDue(calendar: calendar)
            } else {
                reassert(beat)
                // a due schedule preempts the active lock (quick lock, or a different/earlier rule)
                applyScheduledStartIfDue(calendar: calendar)
            }
        } else {
            applyScheduledStartIfDue(calendar: calendar)
        }
    }

    private func applyScheduledStartIfDue(calendar: Calendar) {
        let now = currentTrustedWallNow()
        let decision = Scheduler.evaluate(loadConfig(), at: now, calendar: calendar)
        guard decision.shouldBlock, let rule = decision.activeRule else { return }
        startScheduled(rule: rule, windowEnd: decision.windowEnd)
    }
}
