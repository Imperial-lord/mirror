import Foundation
import CryptoKit

struct PersonBiography: Codable {
    let birthName: String?
    let birthDate: String?
    let birthPlace: String?
    let portrait: URL?
    let imageSource: URL?
    let entity: URL?
}

actor PeopleMetadataService {
    static let shared = PeopleMetadataService()
    private struct Entry: Codable { let data: Data; let expires: Date }
    private var cache: [String: Entry] = [:]
    private var pending: [String: Task<Data, Error>] = [:]
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("people-metadata", isDirectory: true)

    private struct Value: Decodable { let value: String }
    private struct Response: Decodable {
        struct Results: Decodable { let bindings: [[String: Value]] }
        let results: Results
    }

    private func rows(_ query: String) async throws -> [[String: Value]] {
        var url = URLComponents(string: "https://query.wikidata.org/sparql")!
        url.queryItems = [.init(name: "query", value: query), .init(name: "format", value: "json")]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 25
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.setValue("MirrorMovieApp/1.0 (IMDb-linked movie credits)", forHTTPHeaderField: "User-Agent")
        return try JSONDecoder().decode(Response.self, from: await data(request)).results.bindings
    }

    private func data(_ request: URLRequest) async throws -> Data {
        let key = request.url!.absoluteString
        if let entry = cache[key], entry.expires > Date() { return entry.data }
        // The persistent file uses a stable SHA-256 name, keeping queries out of file paths.
        let file = directory?.appendingPathComponent(Self.digest(key))
        if let file, let bytes = try? Data(contentsOf: file),
           let entry = try? JSONDecoder().decode(Entry.self, from: bytes), entry.expires > Date() {
            cache[key] = entry
            return entry.data
        }
        if let task = pending[key] { return try await task.value }
        let task = Task {
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count < 4_000_000 else {
                throw URLError(.badServerResponse)
            }
            return bytes
        }
        pending[key] = task
        defer { pending[key] = nil }
        let bytes = try await task.value
        let entry = Entry(data: bytes, expires: Date().addingTimeInterval(7 * 86400))
        if cache.count >= 128 { cache.removeAll() }
        cache[key] = entry
        if let directory, let file, let stored = try? JSONEncoder().encode(entry) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? stored.write(to: file, options: .atomic)
        }
        return bytes
    }

    func credits(movieIMDb: String) async throws -> [Cast] {
        guard movieIMDb.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil else { return [] }
        let result = try await rows("""
        SELECT DISTINCT ?person ?personLabel ?imdb ?image ?job ?characterName ?characterLabel WHERE {
          ?film wdt:P345 "\(movieIMDb)".
          VALUES (?property ?job) { (wdt:P161 "Actor") (wdt:P57 "Director") (wdt:P58 "Writer") (wdt:P162 "Producer") (wdt:P86 "Composer") }
          ?film ?property ?person.
          OPTIONAL { ?person wdt:P345 ?imdb }
          OPTIONAL { ?person wdt:P18 ?image }
          OPTIONAL {
            ?film p:P161 ?castStatement. ?castStatement ps:P161 ?person.
            OPTIONAL { ?castStatement pq:P4633 ?characterName }
            OPTIONAL { ?castStatement pq:P453 ?character. ?character rdfs:label ?characterLabel. FILTER(LANG(?characterLabel) = "en") }
          }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } ORDER BY ?job ?person ?image LIMIT 100
        """)
        var people: [Cast] = []
        for row in result {
            guard let name = row["personLabel"]?.value,
                  name.range(of: "^Q[0-9]+$", options: .regularExpression) == nil,
                  let entity = row["person"]?.value.components(separatedBy: "/").last else { continue }
            let imdb = row["imdb"]?.value
            let job = row["job"]?.value ?? "Actor"
            let character = job == "Actor" ? (row["characterName"]?.value ?? row["characterLabel"]?.value) : nil
            var person = Cast(name: name, characterName: character,
                              urlSmallImage: portrait(row["image"]?.value)?.absoluteString,
                              imdbCode: imdb)
            person.entityID = entity
            person.department = job
            if !people.contains(where: { $0.id == person.id }) { people.append(person) }
        }
        return people
    }

    func biography(_ person: Cast) async throws -> PersonBiography? {
        if let entityID = person.entityID, entityID.range(of: "^Q[0-9]+$", options: .regularExpression) != nil {
            let entity = try await entityData(entityID)
            let claims = entity["claims"] as? [String: [[String: Any]]] ?? [:]
            func claim(_ property: String) -> Any? {
                let snak = claims[property]?.first?["mainsnak"] as? [String: Any]
                return (snak?["datavalue"] as? [String: Any])?["value"]
            }
            let image = person.avatarURL?.lastPathComponent ?? claim("P18") as? String
            var place: String?
            if let id = (claim("P19") as? [String: Any])?["id"] as? String,
               let location = try? await entityData(id),
               let labels = location["labels"] as? [String: [String: String]] {
                place = labels["en"]?["value"]
            }
            var photo = URLComponents(string: "https://commons.wikimedia.org/wiki/Special:FilePath/")!
            photo.path += image ?? ""
            let imageURL = image == nil ? nil : portrait(photo.url?.absoluteString)
            var source = URLComponents(string: "https://commons.wikimedia.org/w/index.php")!
            source.queryItems = [.init(name: "title", value: "File:" + (image ?? ""))]
            return PersonBiography(birthName: (claim("P1477") as? [String: Any])?["text"] as? String,
                                   birthDate: ((claim("P569") as? [String: Any])?["time"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "+")),
                                   birthPlace: place, portrait: imageURL, imageSource: image == nil ? nil : source.url,
                                   entity: URL(string: "https://www.wikidata.org/wiki/\(entityID)"))
        }
        guard let imdb = person.normalizedIMDbID else { return nil }
        let result = try await rows("""
        SELECT ?person ?birthName ?birth ?placeLabel ?image WHERE {
          ?person wdt:P345 "\(imdb)".
          OPTIONAL { ?person wdt:P1477 ?birthName }
          OPTIONAL { ?person wdt:P569 ?birth }
          OPTIONAL { ?person wdt:P19 ?place }
          OPTIONAL { ?person wdt:P18 ?image }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } LIMIT 1
        """)
        guard let row = result.first else { return nil }
        let image = row["image"]?.value
        let filename = image.flatMap { URL(string: $0)?.lastPathComponent }
        let source = filename.flatMap { name -> URL? in
            var url = URLComponents(string: "https://commons.wikimedia.org/w/index.php")!
            url.queryItems = [.init(name: "title", value: "File:" + name)]
            return url.url
        }
        return PersonBiography(birthName: row["birthName"]?.value,
                               birthDate: row["birth"]?.value,
                               birthPlace: row["placeLabel"]?.value,
                               portrait: portrait(image), imageSource: source,
                               entity: row["person"].flatMap { URL(string: $0.value.replacingOccurrences(of: "http:", with: "https:")) })
    }

    private func entityData(_ id: String) async throws -> [String: Any] {
        guard id.range(of: "^Q[0-9]+$", options: .regularExpression) != nil else { throw URLError(.badURL) }
        var request = URLRequest(url: URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(id).json")!)
        request.timeoutInterval = 20
        request.setValue("MirrorMovieApp/1.0 (person biography)", forHTTPHeaderField: "User-Agent")
        let object = try JSONSerialization.jsonObject(with: await data(request)) as? [String: Any]
        guard let entities = object?["entities"] as? [String: [String: Any]], let entity = entities[id] else {
            throw URLError(.cannotParseResponse)
        }
        return entity
    }

    func filmography(_ person: Cast) async throws -> [Movie] {
        let identity: String
        if let entity = person.entityID, entity.range(of: "^Q[0-9]+$", options: .regularExpression) != nil {
            identity = "VALUES ?person { wd:\(entity) }"
        } else if let imdb = person.normalizedIMDbID {
            identity = "?person wdt:P345 \"\(imdb)\"."
        } else { return [] }
        let result = try await rows("""
        SELECT DISTINCT ?imdb WHERE {
          \(identity)
          ?film (wdt:P161|wdt:P57|wdt:P58|wdt:P162|wdt:P86) ?person; wdt:P345 ?imdb.
          FILTER(STRSTARTS(?imdb, "tt"))
          OPTIONAL { ?film wdt:P577 ?date }
        } ORDER BY DESC(?date) LIMIT 40
        """)
        var visited: Set<String> = []
        let ids = result.compactMap { $0["imdb"]?.value }.filter { visited.insert($0).inserted }
        var movies: [Movie] = []
        // Four lookups at a time keep requests bounded on slow connections.
        for offset in stride(from: 0, to: ids.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(ids[offset..<min(offset + 4, ids.count)])
            let found = try await withThrowingTaskGroup(of: [Movie].self) { group in
                for id in batch {
                    group.addTask {
                        try await MovieRepository.shared.fetchMovies(endpoint: .listMovies(limit: 5, queryTerm: id))
                            .filter { $0.imdbCode == id }
                    }
                }
                var values: [Movie] = []
                for try await rows in group { values += rows }
                return values
            }
            movies += found
        }
        var seen: Set<Int> = []
        return movies.filter { seen.insert($0.id).inserted }.sorted { $0.year > $1.year }
    }

    private func portrait(_ value: String?) -> URL? {
        guard let value, var url = URLComponents(string: value), url.host == "commons.wikimedia.org" else { return nil }
        url.scheme = "https"
        url.queryItems = [.init(name: "width", value: "960")]
        return url.url
    }
}
private extension PeopleMetadataService {
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
