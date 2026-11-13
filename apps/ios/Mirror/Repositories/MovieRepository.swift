import Foundation

public struct YearMoviePage: Decodable {
    public let movies: [Movie]
    public let hasMore: Bool
}

public protocol MovieRepositoryProtocol: Sendable {
    func fetchYearMovies(endpoint: APIEndpoint, year: Int) async throws -> YearMoviePage
    func fetchMovies(endpoint: APIEndpoint) async throws -> [Movie]
    func fetchMovieDetail(id: Int) async throws -> MovieDetail
    func fetchSuggestions(movieId: Int) async throws -> [Movie]
}

public extension MovieRepositoryProtocol {
    func fetchYearMovies(endpoint: APIEndpoint, year: Int) async throws -> YearMoviePage {
        let movies = try await fetchMovies(endpoint: endpoint)
        let limit = Int(endpoint.queryItems.first { $0.name == "limit" }?.value ?? "30") ?? 30
        return YearMoviePage(movies: movies.filter { $0.year == year }, hasMore: movies.count == limit)
    }
}

public final class MovieRepository: MovieRepositoryProtocol {
    public static let shared = MovieRepository()
    private let client: APIClient

    public init(client: APIClient = .shared) {
        self.client = client
    }

    public func fetchMovies(endpoint: APIEndpoint) async throws -> [Movie] {
        let response: YTSResponse<MovieListData> = try await client.fetch(endpoint)
        return response.data.movies ?? []
    }

    public func fetchYearMovies(endpoint: APIEndpoint, year: Int) async throws -> YearMoviePage {
        let service = await PlaybackService()
        return try await service.yearMovies(endpoint: endpoint, year: year)
    }

    public func fetchMovieDetail(id: Int) async throws -> MovieDetail {
        let endpoint = APIEndpoint.movieDetails(movieId: id)
        let response: YTSResponse<MovieDetailData> = try await client.fetch(endpoint)
        return response.data.movie
    }

    public func fetchSuggestions(movieId: Int) async throws -> [Movie] {
        let endpoint = APIEndpoint.movieSuggestions(movieId: movieId)
        let response: YTSResponse<MovieSuggestionsData> = try await client.fetch(endpoint)
        return response.data.movies ?? []
    }
}
