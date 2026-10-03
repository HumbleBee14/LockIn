import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var status: DaemonStatus?
    @Published var reachable = true
    @Published var everConnected = false
    private let client: DaemonClient

    init(client: DaemonClient) { self.client = client }

    var isActive: Bool { status?.active ?? false }

    // only treat "unreachable" as a hold-the-UI signal AFTER we've actually connected once.
    // a cold start that never reached the daemon must fall through to the normal install/Approve flow,
    // never trap the user on a Reconnecting screen.
    var lostConnection: Bool { everConnected && !reachable }

    var canAddDomains: Bool {
        guard isActive else { return false }
        if let locks = status?.locks { return locks.contains { !$0.isAllowlist } }
        return !(status?.isAllowlist ?? false)   // old daemon: aggregate fallback
    }

    // blocklist locks currently holding each set, so the lock screen can say where an added site lands
    var activeBlocklistLocks: [ActiveLockInfo] { (status?.locks ?? []).filter { !$0.isAllowlist } }

    // "+ New Lock" needs a daemon that reports per-lock status — an old daemon refuses every stack
    var canStackLock: Bool { isActive && status?.locks != nil }

    var countdownText: String {
        guard let end = status?.endsAt else { return "" }
        return countdown(to: end)
    }

    func countdown(to end: Date) -> String {
        let remaining = max(0, Int(end.timeIntervalSinceNow))
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        let s = remaining % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    func endTimeString(_ end: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "HH:mm:ss"
        return f.string(from: end)
    }

    func refresh() async {
        switch await client.statusResult() {
        case .answered(let s): status = s; reachable = true; everConnected = true
        case .unreachable: reachable = false
        }
    }

    // nil on success; otherwise the failure reason to surface
    func startQuickLock(blockSetIds: [String], minutes: Int) async -> String? {
        await client.startQuickLock(blockSetIds: blockSetIds, duration: Double(minutes * 60))
    }

    enum AddResult: Equatable {
        case failed(String)
        case added(until: Date?, warning: String?)   // warning: blocked now, but not fully saved to the set
    }

    // the site is blocked now, in the lock holding the chosen set (or the longest-lived lock if none does),
    // and saved into that set for later locks. a full set is refused up front, before anything is blocked.
    func addDomains(_ domains: [String], toBlockSet id: String, persistingTo store: ScheduleStore) async -> AddResult {
        guard let set = store.config.blockSets.first(where: { $0.id == id }) else {
            return .failed("That block set no longer exists.")
        }
        let existing = Set(set.domains)
        guard existing.count + Set(domains).subtracting(existing).count <= BlockLimits.maxActiveDomains else {
            return .failed("\(set.name) already holds the maximum of \(BlockLimits.maxActiveDomains) sites. Pick another set.")
        }
        let (reason, until) = await client.appendDomainsReason(domains, toBlockSet: id)
        await refresh()
        if let reason { return .failed(reason) }
        let outcome = store.addDomains(domains, toBlockSet: id)
        if outcome.hitCap {
            return .added(until: until, warning: "Blocked for this lock, but \(set.name) is full, so it won't be saved for later locks.")
        }
        // always sync: a retry after a failed sync finds the site already saved here (added == 0)
        if !(await store.commit()) {
            return .added(until: until, warning: "Blocked for this lock and saved on this Mac, but the blocker didn't confirm the set update. Edit the set after the lock to re-save it.")
        }
        return .added(until: until, warning: nil)
    }
}
