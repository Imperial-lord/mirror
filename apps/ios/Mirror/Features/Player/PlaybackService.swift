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

    private func baseURL() throws -> URL {
        let configured = UserDefaults.standard.string(forKey: "PlaybackServiceURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "PlaybackServiceURL") as? String
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
