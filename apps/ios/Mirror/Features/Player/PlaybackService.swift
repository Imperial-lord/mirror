import Foundation
import FirebaseAuth

struct PlaybackSession: Decodable {
    let id: String
    let path: String
}

@MainActor
final class PlaybackService {
    enum Failure: LocalizedError {
        case serviceUnavailable, busy, sourceUnavailable, unsupportedVideo

        var errorDescription: String? {
            switch self {
            case .serviceUnavailable: return "Cannot connect to playback. Please try again shortly."
            case .busy: return "The streaming service is busy. Try again in a moment."
            case .sourceUnavailable: return "This source took too long to respond. Try again or choose another quality."
            case .unsupportedVideo: return "This source has no playable video. Choose another quality."
            }
        }
    }

    private var active: (URL, String)?
    private var generation = UUID()

    func open(hash: String) async throws -> URL {
        close()
        let requestGeneration = generation
        let base = try baseURL()
        var request = URLRequest(url: base.appendingPathComponent("v1/sessions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let user = Auth.auth().currentUser {
            request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(["hash": hash])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet].contains(error.code) {
            throw Failure.serviceUnavailable
        }
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch response.statusCode {
        case 201: break
        case 503: throw Failure.busy
        case 502, 504: throw Failure.sourceUnavailable
        case 422: throw Failure.unsupportedVideo
        default: throw URLError(.cannotLoadFromNetwork)
        }
        let session = try JSONDecoder().decode(PlaybackSession.self, from: data)
        if Task.isCancelled || requestGeneration != generation {
            release(base: base, id: session.id)
            throw CancellationError()
        }
        active = (base, session.id)
        guard let url = URL(string: session.path, relativeTo: base), url.host == base.host else { throw URLError(.badServerResponse) }
        return url.absoluteURL
    }

    func yearMovies(endpoint: APIEndpoint, year: Int) async throws -> YearMoviePage {
        let base = try baseURL()
        var url = URLComponents(url: base.appendingPathComponent("v1/catalog"), resolvingAgainstBaseURL: true)!
        url.queryItems = endpoint.queryItems + [URLQueryItem(name: "year", value: String(year))]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 120
        if let user = Auth.auth().currentUser {
            request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.cannotLoadFromNetwork) }
        return try JSONDecoder().decode(YearMoviePage.self, from: data)
    }

    func subtitles(imdb: String, language: String) async throws -> SubtitleTrack {
        let base = try baseURL()
        var request = URLRequest(url: base.appendingPathComponent("v1/subtitles/\(imdb)/\(language)"))
        request.timeoutInterval = 90
        if let user = Auth.auth().currentUser {
            request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.resourceUnavailable) }
        return try JSONDecoder().decode(SubtitleTrack.self, from: data)
    }

    static func homePreview(movieID: Int) async throws -> URL? {
        guard let endpoint = homePreviewsEndpoint,
              var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        url.queryItems = [URLQueryItem(name: "movie_id", value: String(movieID))]
        guard let lookupURL = url.url else { return nil }
        return try await fetchHomePreviews(URLRequest(url: lookupURL), movieIDs: [movieID])[movieID]
    }

    static func reportHomePreviews(_ ids: [Int]) async throws -> [Int: URL] {
        guard let endpoint = homePreviewsEndpoint else { return [:] }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Array(ids.prefix(320)))
        return try await fetchHomePreviews(request, movieIDs: Set(ids))
    }

    private static var homePreviewsEndpoint: URL? {
        guard let configured = configuredBaseAddress, let base = URL(string: configured),
              base.scheme == "https", base.host != nil else { return nil }
        return base.appendingPathComponent("v1/home-previews")
    }

    private static func fetchHomePreviews(_ request: URLRequest, movieIDs: Set<Int>) async throws -> [Int: URL] {
        guard let user = Auth.auth().currentUser else { return [:] }
        var request = request
        request.timeoutInterval = 8
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 512 * 1024
        else { throw URLError(.badServerResponse) }
        let clips = try JSONDecoder().decode([Int: URL].self, from: data)
        return clips.filter { id, url in
            guard let host = url.host, url.scheme == "https", movieIDs.contains(id) else { return false }
            return host.hasPrefix("objectstorage.") && host.hasSuffix(".oraclecloud.com")
        }
    }

    private static var configuredBaseAddress: String? {
        UserDefaults.standard.string(forKey: "PlaybackServiceURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "PlaybackServiceURL") as? String
    }

    private func baseURL() throws -> URL {
        let configured = Self.configuredBaseAddress
        #if targetEnvironment(simulator)
        let address = configured ?? "http://127.0.0.1:8787"
        #else
        guard let address = configured else { throw URLError(.badURL) }
        #endif
        guard let base = URL(string: address), ["http", "https"].contains(base.scheme ?? "") else { throw URLError(.badURL) }
        return base
    }

    func close() {
        generation = UUID()
        if let (base, id) = active { release(base: base, id: id) }
        active = nil
    }
    private func release(base: URL, id: String) {
        var request = URLRequest(url: base.appendingPathComponent("v1/sessions/\(id)"))
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request).resume()
    }
}
