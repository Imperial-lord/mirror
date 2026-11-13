import Foundation

public struct Movie: Codable, Identifiable, Hashable {
    public let id: Int
    public let url: String
    public let imdbCode: String
    public let title: String
    public let titleEnglish: String?
    public let titleLong: String?
    public let slug: String?
    public let year: Int
    public let rating: Double
    public let runtime: Int
    public let genres: [String]?
    public let summary: String?
    public let descriptionFull: String?
    public let synopsis: String?
    public let ytTrailerCode: String?
    public let language: String?
    public let mpaRating: String?
    public let backgroundImage: String?
    public let backgroundImageOriginal: String?
    public let smallCoverImage: String?
    public let mediumCoverImage: String?
    public let largeCoverImage: String?
    public let state: String?
    public let torrents: [Torrent]?
    public let dateUploaded: String?

    public var formattedRuntime: String {
        let hours = runtime / 60
        let minutes = runtime % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func sanitizeURL(_ urlString: String?) -> URL? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }
        var normalized = urlString.replacingOccurrences(of: "https://yts.mx/", with: "https://img.yts.gg/")
        normalized = normalized.replacingOccurrences(of: "https://yts.gg/", with: "https://img.yts.gg/")
        normalized = normalized.replacingOccurrences(of: "http://", with: "https://")
        return URL(string: normalized)
    }

    public var posterURL: URL? {
        Self.sanitizeURL(largeCoverImage ?? mediumCoverImage ?? smallCoverImage)
    }

    public var largePosterURL: URL? {
        Self.sanitizeURL(largeCoverImage ?? mediumCoverImage ?? smallCoverImage)
    }

    public var mediumPosterURL: URL? {
        Self.sanitizeURL(mediumCoverImage ?? largeCoverImage ?? smallCoverImage)
    }

    public var backdropURL: URL? {
        Self.sanitizeURL(backgroundImageOriginal ?? backgroundImage)
    }

    public var trailerURL: URL? {
        guard let code = ytTrailerCode, !code.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(code)")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case imdbCode = "imdb_code"
        case title
        case titleEnglish = "title_english"
        case titleLong = "title_long"
        case slug
        case year
        case rating
        case runtime
        case genres
        case summary
        case descriptionFull = "description_full"
        case synopsis
        case ytTrailerCode = "yt_trailer_code"
        case language
        case mpaRating = "mpa_rating"
        case backgroundImage = "background_image"
        case backgroundImageOriginal = "background_image_original"
        case smallCoverImage = "small_cover_image"
        case mediumCoverImage = "medium_cover_image"
        case largeCoverImage = "large_cover_image"
        case state
        case torrents
        case dateUploaded = "date_uploaded"
    }
}
