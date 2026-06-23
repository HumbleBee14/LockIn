import Foundation

struct BlockCategory: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var sourceURL: String?
}

struct CategoryCatalog: Codable, Equatable {
    var categories: [BlockCategory]
}

enum CategoryCatalogLoader {
    static func load() -> [BlockCategory] {
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(CategoryCatalog.self, from: data) else {
            return []
        }
        return catalog.categories
    }
}
