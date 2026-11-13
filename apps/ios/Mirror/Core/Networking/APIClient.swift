import Foundation

public actor APIClient {
    public static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    public func invalidateResponses() { responses.removeAll(); session.configuration.urlCache?.removeAllCachedResponses() }

    private var responses: [URL: (data: Data, expires: Date)] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 50_000_000,  // 50 MB
            diskCapacity: 200_000_000    // 200 MB
        )
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        // Note: Models use explicit CodingKeys to match YTS snake_case responses reliably
    }

    public func fetch<T: Codable>(_ endpoint: APIEndpoint) async throws -> T {
        guard let url = endpoint.url else {
            throw APIError.invalidURL
        }

        if let cached = responses[url], cached.expires > Date() {
            return try decoder.decode(T.self, from: cached.data)
        }
        let data: Data
        let response: URLResponse
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        do {
            let decoded = try decoder.decode(T.self, from: data)
            responses = responses.filter { $0.value.expires > Date() }
            if responses.count >= 128 { responses.removeAll() }
            responses[url] = (data, Date().addingTimeInterval(3600))
            return decoded
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
