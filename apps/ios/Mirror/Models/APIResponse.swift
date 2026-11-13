import Foundation

public struct YTSResponse<T: Codable>: Codable {
    public let status: String
    public let statusMessage: String
    public let data: T

    enum CodingKeys: String, CodingKey {
        case status
        case statusMessage = "status_message"
        case data
    }
}

public struct MovieListData: Codable {
    public let movieCount: Int
    public let limit: Int
    public let pageNumber: Int
    public let movies: [Movie]?

    enum CodingKeys: String, CodingKey {
        case movieCount = "movie_count"
        case limit
        case pageNumber = "page_number"
        case movies
    }
}

public struct MovieDetailData: Codable {
    public let movie: MovieDetail
}

public struct MovieSuggestionsData: Codable {
    public let movieCount: Int
    public let movies: [Movie]?

    enum CodingKeys: String, CodingKey {
        case movieCount = "movie_count"
        case movies
    }
}
