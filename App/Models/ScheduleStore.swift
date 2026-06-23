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

    func importPreset(_ preset: Preset) {
        addBlockSet(preset.blockSet)
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

    // Parses a pasted list or hosts-file body into bare domains: strips comments, "0.0.0.0"/"127.0.0.1"
    // host-file prefixes, schemes, paths, and ports. One domain per line.
    nonisolated static func parseDomainList(_ text: String) -> [String] {
        var out: [String] = []
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var token = line
            for prefix in ["0.0.0.0", "127.0.0.1", "::1"] {
                if token.hasPrefix(prefix) {
                    token = String(token.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                }
            }
            token = token.replacingOccurrences(of: "https://", with: "")
            token = token.replacingOccurrences(of: "http://", with: "")
            if let slash = token.firstIndex(of: "/") { token = String(token[..<slash]) }
            if let colon = token.firstIndex(of: ":") { token = String(token[..<colon]) }
            token = token.trimmingCharacters(in: .whitespaces).lowercased()
            if token.contains("."), !out.contains(token) { out.append(token) }
        }
        return out
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
