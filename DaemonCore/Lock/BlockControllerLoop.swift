import Foundation

extension BlockController {
    public func applyDecisionIfNeeded(timeResolved: Bool, calendar: Calendar = .current) {
        guard let state = loadState() else {
            applyScheduledStartIfDue(calendar: calendar)
            return
        }
        if state.active {
            // boot-race rule: never tear down without a resolved time source (bias to blocked).
            guard timeResolved else { return }
            let beat = guardHeartbeat(state)
            saveState(beat)
            if guardIsExpired(beat) {
                clearBlocking()
                clearState()
                pushClearedSnapshot()
            } else {
                reassert(domains: beat.appliedDomains)
            }
        } else {
            applyScheduledStartIfDue(calendar: calendar)
        }
    }

    private func applyScheduledStartIfDue(calendar: Calendar) {
        let now = currentTrustedWallNow()
        let decision = Scheduler.evaluate(loadConfig(), at: now, calendar: calendar)
        guard decision.shouldBlock, let rule = decision.activeRule else { return }
        let domains = resolveDomains(forBlockSetId: rule.blockSetId)
        startScheduled(rule: rule, windowEnd: decision.windowEnd, domains: domains,
                       appBundleIds: rule.appBundleIds)
    }
}
