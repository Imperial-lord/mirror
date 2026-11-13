import Foundation

public enum Route: Hashable {
    case movieDetail(movieId: Int)
    case personDetail(person: Cast)
    case castAndCrew(people: [Cast])
    case seeAll(title: String, movies: [Movie])
    case watchlist
    case watchHistory
    case settings
    case about
    case genreGrid(genre: Genre)
}
