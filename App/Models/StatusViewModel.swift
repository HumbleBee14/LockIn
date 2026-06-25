import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var status: DaemonStatus?
    private let client: DaemonClient

    init(client: DaemonClient) { self.client = client }

    var isActive: Bool { status?.active ?? false }

    var canAddDomains: Bool { isActive && !(status?.isAllowlist ?? false) }

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
        status = await client.status()
    }

    func startQuickLock(blockSetIds: [String], minutes: Int) async -> Bool {
        await client.startQuickLock(blockSetIds: blockSetIds, duration: Double(minutes * 60))
    }

    func addDomains(_ domains: [String], persistingTo store: ScheduleStore?) async -> Bool {
        let ok = await client.appendDomains(domains)
        if ok, let store, let id = status?.blockSetId, !id.isEmpty {
            store.addDomains(domains, toBlockSet: id)
            _ = await store.commit()
        }
        await refresh()
        return ok
    }
}
