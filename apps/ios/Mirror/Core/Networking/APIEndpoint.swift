import Foundation

public enum APIEndpoint {
    case listMovies(
        limit: Int = 20,
        page: Int = 1,
        quality: String? = nil,
        minimumRating: Int? = nil,
        queryTerm: String? = nil,
        genre: String? = nil,
        sortBy: String = "date_added",
        orderBy: String = "desc"
    )
    case movieDetails(movieId: Int, withImages: Bool = true, withCast: Bool = true)
    case movieSuggestions(movieId: Int)

    public var path: String {
        switch self {
        case .listMovies:
            return "list_movies.json"
        case .movieDetails:
            return "movie_details.json"
        case .movieSuggestions:
            return "movie_suggestions.json"
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .listMovies(let limit, let page, let quality, let minRating, let query, let genre, let sort, let order):
            var items: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "sort_by", value: sort),
                URLQueryItem(name: "order_by", value: order)
            ]
            if let quality, !quality.isEmpty {
                items.append(URLQueryItem(name: "quality", value: quality))
            }
            if let minRating {
                items.append(URLQueryItem(name: "minimum_rating", value: "\(minRating)"))
            }
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                items.append(URLQueryItem(name: "query_term", value: query))
            }
            if let genre, genre != "All", !genre.isEmpty {
                items.append(URLQueryItem(name: "genre", value: genre))
            }
            return items

        case .movieDetails(let id, let images, let cast):
            return [
                URLQueryItem(name: "movie_id", value: "\(id)"),
                URLQueryItem(name: "with_images", value: images ? "true" : "false"),
                URLQueryItem(name: "with_cast", value: cast ? "true" : "false")
            ]

        case .movieSuggestions(let id):
            return [
                URLQueryItem(name: "movie_id", value: "\(id)")
            ]
        }
    }

    public var url: URL? {
        var components = URLComponents(string: "https://movies-api.accel.li/api/v2/\(path)")
        components?.queryItems = queryItems
        return components?.url
    }
}
