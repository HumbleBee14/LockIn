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

    static func normalize(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespaces)
        if let hash = token.firstIndex(of: "#") { token = String(token[..<hash]) }
        token = token.trimmingCharacters(in: .whitespaces)
        token = token.replacingOccurrences(of: "https://", with: "")
        token = token.replacingOccurrences(of: "http://", with: "")
        if let slash = token.firstIndex(of: "/") { token = String(token[..<slash]) }
        if let colon = token.firstIndex(of: ":") { token = String(token[..<colon]) }
        token = token.trimmingCharacters(in: .whitespaces).lowercased()
        return token.contains(".") ? token : nil
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
