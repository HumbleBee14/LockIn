import Foundation

protocol DomainListAdaptor: Sendable {
    func canParse(_ text: String) -> Bool
    func extract(from line: String) -> String?
}

enum DomainListImporter {
    static let adaptors: [DomainListAdaptor] = [
        HostsFileAdaptor(),
        AdBlockAdaptor(),
        CSVAdaptor(),
        PlainListAdaptor(),
    ]

    static func parse(_ text: String) -> [String] {
        let adaptor = adaptors.first { $0.canParse(text) } ?? PlainListAdaptor()
        var out: [String] = []
        var seen = Set<String>()
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            guard let domain = adaptor.extract(from: line), seen.insert(domain).inserted else { continue }
            out.append(domain)
        }
        return out
    }

    // one domain per line, sorted — round-trips back through parse()
    static func export(_ domains: [String]) -> String {
        domains.sorted().joined(separator: "\n") + "\n"
    }

    static func normalize(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespaces)
        if let hash = token.firstIndex(of: "#") { token = String(token[..<hash]) }
        token = token.trimmingCharacters(in: .whitespaces)
        token = token.replacingOccurrences(of: "https://", with: "")
        token = token.replacingOccurrences(of: "http://", with: "")
        if let at = token.lastIndex(of: "@") { token = String(token[token.index(after: at)...]) }
        if let slash = token.firstIndex(of: "/") { token = String(token[..<slash]) }
        if let colon = token.firstIndex(of: ":") { token = String(token[..<colon]) }
        if token.hasSuffix(".") { token = String(token.dropLast()) }
        token = token.trimmingCharacters(in: .whitespaces).lowercased()
        return isValidDomain(token) ? token : nil
    }

    static func isValidDomain(_ s: String) -> Bool {
        guard s.count >= 3, s.count <= 253, s.contains(".") else { return false }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count) else { return false }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            for ch in label where !(ch.isLetter || ch.isNumber || ch == "-") { return false }
        }
        guard let tld = labels.last, tld.allSatisfy({ $0.isLetter }) else { return false }
        return true
    }
}

struct PlainListAdaptor: DomainListAdaptor {
    func canParse(_ text: String) -> Bool { true }
    func extract(from line: String) -> String? { DomainListImporter.normalize(line) }
}

struct HostsFileAdaptor: DomainListAdaptor {
    private let prefixes = ["0.0.0.0", "127.0.0.1", "::1"]
    func canParse(_ text: String) -> Bool {
        prefixes.contains { text.contains($0 + " ") || text.contains($0 + "\t") }
    }
    func extract(from line: String) -> String? {
        var token = line.trimmingCharacters(in: .whitespaces)
        if let hash = token.firstIndex(of: "#") { token = String(token[..<hash]) }
        for prefix in prefixes where token.hasPrefix(prefix) {
            token = String(token.dropFirst(prefix.count))
        }
        return DomainListImporter.normalize(token)
    }
}

struct AdBlockAdaptor: DomainListAdaptor {
    func canParse(_ text: String) -> Bool { text.contains("||") && text.contains("^") }
    func extract(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("||") else { return nil }
        var token = String(trimmed.dropFirst(2))
        if let caret = token.firstIndex(of: "^") { token = String(token[..<caret]) }
        return DomainListImporter.normalize(token)
    }
}

struct CSVAdaptor: DomainListAdaptor {
    func canParse(_ text: String) -> Bool {
        let head = text.prefix(while: { $0 != "\n" })
        return head.contains(",")
    }
    func extract(from line: String) -> String? {
        guard let first = line.split(separator: ",").first else { return nil }
        return DomainListImporter.normalize(String(first))
    }
}
