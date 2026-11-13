import Foundation
import SwiftData

@Model
public final class WatchlistItem {
    @Attribute(.unique) public var movieId: Int
    public var title: String
    public var posterURL: String?
    public var backdropURL: String?
    public var year: Int
    public var rating: Double
    public var genres: [String]
    public var dateAdded: Date

    public init(
        movieId: Int,
        title: String,
        posterURL: String?,
        backdropURL: String?,
        year: Int,
        rating: Double,
        genres: [String],
        dateAdded: Date = Date()
    ) {
        self.movieId = movieId
        self.title = title
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.year = year
        self.rating = rating
        self.genres = genres
        self.dateAdded = dateAdded
    }

    public convenience init(movie: Movie) {
        self.init(
            movieId: movie.id,
            title: movie.title,
            posterURL: movie.largeCoverImage ?? movie.mediumCoverImage,
            backdropURL: movie.backgroundImageOriginal ?? movie.backgroundImage,
            year: movie.year,
            rating: movie.rating,
            genres: movie.genres ?? []
        )
    }
}
