import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var status: DaemonStatus?
    private let client: DaemonClient

    init(client: DaemonClient) { self.client = client }

    var isActive: Bool { status?.active ?? false }

    var countdownText: String {
        guard let end = status?.windowEnd else { return "" }
        return countdown(to: end)
    }

    func countdown(to end: Date) -> String {
        let remaining = max(0, Int(end.timeIntervalSinceNow))
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        return "\(h)h \(m)m"
    }

    func refresh() async {
        status = await client.status()
    }
}
