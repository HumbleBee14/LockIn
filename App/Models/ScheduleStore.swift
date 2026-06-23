import Foundation

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var config: ScheduleConfig
    private let client: DaemonClient

    init(client: DaemonClient, config: ScheduleConfig = ScheduleConfig(rules: [])) {
        self.client = client
        self.config = config
    }

    func addRule(_ rule: Rule) {
        config.rules.append(rule)
    }

    func removeRule(id: String) {
        config.rules.removeAll { $0.id == id }
    }

    func addBlockSet(_ set: BlockSet) {
        if let idx = config.blockSets.firstIndex(where: { $0.id == set.id }) {
            config.blockSets[idx] = set
        } else {
            config.blockSets.append(set)
        }
    }

    func removeBlockSet(id: String) {
        config.blockSets.removeAll { $0.id == id }
    }

    // creates the category's block set, then fetches its domains from the remote source (nothing hardcoded)
    func importCategory(_ category: BlockCategory) async -> Bool {
        addBlockSet(BlockSet(id: category.id, name: category.name, domains: [], appBundleIds: []))
        guard let urlString = category.sourceURL, let url = URL(string: urlString) else {
            return await commit()
        }
        return await importRemoteList(into: category.id, from: url)
    }

    func importDomains(into blockSetId: String, from text: String) {
        let parsed = Self.parseDomainList(text)
        guard !parsed.isEmpty else { return }
        if let idx = config.blockSets.firstIndex(where: { $0.id == blockSetId }) {
            var merged = config.blockSets[idx].domains
            for d in parsed where !merged.contains(d) { merged.append(d) }
            config.blockSets[idx].domains = merged
        } else {
            addBlockSet(BlockSet(id: blockSetId, name: blockSetId, domains: parsed, appBundleIds: []))
        }
    }

    // delegates to DomainListImporter, which auto-detects format (plain / hosts / AdBlock / CSV)
    nonisolated static func parseDomainList(_ text: String) -> [String] {
        DomainListImporter.parse(text)
    }

    func importFile(into blockSetId: String, at url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        importDomains(into: blockSetId, from: text)
        return true
    }

    func importRemoteList(into blockSetId: String, from url: URL) async -> Bool {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        importDomains(into: blockSetId, from: text)
        return await commit()
    }

    func commit() async -> Bool {
        await client.registerSchedule(config)
    }
}
