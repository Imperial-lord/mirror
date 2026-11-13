import Foundation

struct CatalogProduction: Codable, Sendable {
    var countries: Set<String> = []
    var studios: Set<String> = []
}

protocol CatalogMetadataProviding: Sendable {
    func production(for movies: [Movie]) async throws -> [String: CatalogProduction]
}

struct CatalogFilterOption: Identifiable {
    let id: String
    let name: String
    static let countries: [Self] = [
        .init(id: "Q30", name: "United States"), .init(id: "Q145", name: "United Kingdom"),
        .init(id: "Q16", name: "Canada"), .init(id: "Q408", name: "Australia"),
        .init(id: "Q142", name: "France"), .init(id: "Q183", name: "Germany"),
        .init(id: "Q38", name: "Italy"), .init(id: "Q29", name: "Spain"),
        .init(id: "Q668", name: "India"), .init(id: "Q17", name: "Japan"),
        .init(id: "Q884", name: "South Korea")
    ]
    static let studios: [Self] = [
        .init(id: "Q367466", name: "Marvel Studios"),
        .init(id: "Q126399", name: "Warner Bros. Entertainment"),
        .init(id: "Q168383", name: "Universal Pictures"),
        .init(id: "Q159846", name: "Paramount Pictures"),
        .init(id: "Q191224", name: "Walt Disney Pictures"),
        .init(id: "Q179200", name: "Metro-Goldwyn-Mayer")
    ]
}

// Production metadata is joined by IMDb ID, never inferred from a movie's language.
actor CatalogMetadataService: CatalogMetadataProviding {
    static let shared = CatalogMetadataService()
    private struct Entry: Codable { let expires: Date; let production: CatalogProduction }
    private var cache: [String: Entry] = [:]
    private let file: URL?
    init() {
        file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("catalog-production.json")
        if let file, let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = stored.filter { $0.value.expires > Date() }
        }
    }

    func production(for movies: [Movie]) async throws -> [String: CatalogProduction] {
        let ids = Set(movies.map(\.imdbCode).filter { $0.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil })
        let missing = ids.filter { cache[$0].map { $0.expires <= Date() } ?? true }.sorted()
        // Bound URL length and provider work even if another caller passes a large collection.
        for offset in stride(from: 0, to: missing.count, by: 30) {
            try Task.checkCancellation()
            let batch = Array(missing[offset..<min(offset + 30, missing.count)])
            let values = batch.map { "\"\($0)\"" }.joined(separator: " ")
            let query = "SELECT ?imdb ?country ?studio WHERE { VALUES ?imdb { \(values) } ?film wdt:P345 ?imdb. OPTIONAL { ?film wdt:P495 ?country. } OPTIONAL { ?film wdt:P272 ?studio. } }"
            var url = URLComponents(string: "https://query.wikidata.org/sparql")!
            url.queryItems = [.init(name: "query", value: query), .init(name: "format", value: "json")]
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 30
            request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
            request.setValue("MirrorMovieApp/1.0 (catalog production metadata)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let result = try JSONDecoder().decode(Response.self, from: data)
            var found = Dictionary(uniqueKeysWithValues: batch.map { ($0, CatalogProduction()) })
            for row in result.results.bindings {
                guard let imdb = row["imdb"]?.value, found[imdb] != nil else { continue }
                if let country = row["country"]?.value.split(separator: "/").last { found[imdb]?.countries.insert(String(country)) }
                if let studio = row["studio"]?.value.split(separator: "/").last { found[imdb]?.studios.insert(String(studio)) }
            }
            try Task.checkCancellation()
            for (id, production) in found { cache[id] = Entry(expires: Date().addingTimeInterval(7 * 86400), production: production) }
        }
        cache = cache.filter { $0.value.expires > Date() }
        if cache.count > 10_000 { cache = cache.filter { ids.contains($0.key) } }
        if !missing.isEmpty, let file, let data = try? JSONEncoder().encode(cache) { try? data.write(to: file, options: .atomic) }
        return Dictionary(uniqueKeysWithValues: ids.compactMap { id in cache[id].map { (id, $0.production) } })
    }
    private struct Response: Decodable {
        struct Value: Decodable { let value: String }
        struct Results: Decodable { let bindings: [[String: Value]] }
        let results: Results
    }
}
