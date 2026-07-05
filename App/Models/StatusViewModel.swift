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

    // nil on success; otherwise the reason to surface. persists into the daemon-declared append
    // target set (the longest-running blocklist lock's set) — never the aggregate blockSetId.
    func addDomains(_ domains: [String], persistingTo store: ScheduleStore?) async -> String? {
        let reason = await client.appendDomainsReason(domains)
        if reason == nil, let store, let id = status?.appendTargetBlockSetId, !id.isEmpty {
            store.addDomains(domains, toBlockSet: id)
            _ = await store.commit()
        }
        await refresh()
        return reason
    }
}
