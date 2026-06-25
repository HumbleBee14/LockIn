import Foundation

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var config: ScheduleConfig
    private let client: DaemonClient

    init(client: DaemonClient, config: ScheduleConfig? = nil) {
        self.client = client
        self.config = config ?? ConfigPersistence.load() ?? ScheduleConfig(rules: [])
    }

    private func persist() {
        ConfigPersistence.save(config)
    }

    func addRule(_ rule: Rule) {
        config.rules.append(rule)
        persist()
    }

    func removeRule(id: String) {
        config.rules.removeAll { $0.id == id }
        persist()
    }

    func addBlockSet(_ set: BlockSet) {
        if let idx = config.blockSets.firstIndex(where: { $0.id == set.id }) {
            config.blockSets[idx] = set
        } else {
            config.blockSets.append(set)
        }
        persist()
    }

    func removeBlockSet(id: String) {
        config.blockSets.removeAll { $0.id == id }
        persist()
    }

    func setMode(_ mode: BlockSetMode, forBlockSet id: String) {
        guard let idx = config.blockSets.firstIndex(where: { $0.id == id }) else { return }
        config.blockSets[idx].mode = mode
        persist()
    }

    // single gateway for adding domains to a set, capacity-aware so no list can exceed the cap
    struct AddOutcome { let added: Int; let skippedOverCap: Int; var hitCap: Bool { skippedOverCap > 0 } }

    @discardableResult
    func addDomains(_ domains: [String], toBlockSet id: String) -> AddOutcome {
        guard let idx = config.blockSets.firstIndex(where: { $0.id == id }) else {
            return AddOutcome(added: 0, skippedOverCap: 0)
        }
        var existing = Set(config.blockSets[idx].domains)
        var added = 0, skipped = 0
        for d in domains where !existing.contains(d) {
            if existing.count >= BlockLimits.maxActiveDomains { skipped += 1; continue }
            config.blockSets[idx].domains.append(d); existing.insert(d); added += 1
        }
        if added > 0 { persist() }
        return AddOutcome(added: added, skippedOverCap: skipped)
    }

    func removeDomain(_ domain: String, fromBlockSet id: String) {
        guard let idx = config.blockSets.firstIndex(where: { $0.id == id }) else { return }
        config.blockSets[idx].domains.removeAll { $0 == domain }
        persist()
    }

    // apps are always blocklist; the set's mode governs only its websites
    @discardableResult
    func addApps(_ bundleIds: [String], toBlockSet id: String) -> AddOutcome {
        guard let idx = config.blockSets.firstIndex(where: { $0.id == id }) else {
            return AddOutcome(added: 0, skippedOverCap: 0)
        }
        var existing = Set(config.blockSets[idx].appBundleIds)
        var added = 0, skipped = 0
        for b in bundleIds where !b.isEmpty && !existing.contains(b) {
            if existing.count >= BlockLimits.maxActiveDomains { skipped += 1; continue }
            config.blockSets[idx].appBundleIds.append(b); existing.insert(b); added += 1
        }
        if added > 0 { persist() }
        return AddOutcome(added: added, skippedOverCap: skipped)
    }

    func removeApp(_ bundleId: String, fromBlockSet id: String) {
        guard let idx = config.blockSets.firstIndex(where: { $0.id == id }) else { return }
        config.blockSets[idx].appBundleIds.removeAll { $0 == bundleId }
        persist()
    }

    @discardableResult
    func createBlockSet(title: String, mode: BlockSetMode = .blocklist) -> BlockSet {
        let set = BlockSet(id: UUID().uuidString, name: title, domains: [], appBundleIds: [], mode: mode)
        addBlockSet(set)
        return set
    }

    @discardableResult
    func importDomains(into blockSetId: String, from text: String) -> AddOutcome {
        let parsed = Self.parseDomainList(text)
        guard !parsed.isEmpty else { return AddOutcome(added: 0, skippedOverCap: 0) }
        if config.blockSets.firstIndex(where: { $0.id == blockSetId }) == nil {
            addBlockSet(BlockSet(id: blockSetId, name: blockSetId, domains: [], appBundleIds: []))
        }
        return addDomains(parsed, toBlockSet: blockSetId)
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
