import Foundation

struct WatchPreference: Sendable, Equatable {
    let movieId: Int
    let genres: [String]
    let progress: Double
    let lastWatched: Date
    init(movieId: Int, genres: [String], progress: Double, lastWatched: Date) {
        self.movieId = movieId; self.genres = genres; self.progress = progress; self.lastWatched = lastWatched
    }
    init(_ item: WatchHistoryItem) {
        self.init(movieId: item.movieId, genres: item.genres, progress: item.progressPercentage, lastWatched: item.lastWatched)
    }
}

enum WatchPreferences {
    static func rankedGenres(_ history: [WatchPreference]) -> [String] {
        var scores: [String: Double] = [:]
        for (index, item) in history.filter({ $0.progress > 0 }).sorted(by: { $0.lastWatched > $1.lastWatched }).enumerated() {
            for genre in Set(item.genres) where Genre(rawValue: genre) != nil && genre != "All" {
                scores[genre, default: 0] += max(0.1, item.progress) / (1 + Double(index) * 0.1)
            }
        }
        return scores.keys.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0]! > scores[$1]! }
    }
    static func recommend(candidates: [Movie], history: [WatchPreference], limit: Int = 15) -> [Movie] {
        let seen = Set(history.filter { $0.progress > 0 }.map(\.movieId))
        let genres = rankedGenres(history)
        var ids = Set<Int>()
        let unique = candidates.filter { !seen.contains($0.id) && ids.insert($0.id).inserted }
        return Array(unique.enumerated().sorted { lhs, rhs in
            func score(_ movie: Movie) -> Int {
                (movie.genres ?? []).reduce(0) { result, genre in result + (genres.firstIndex(of: genre).map { genres.count - $0 } ?? 0) }
            }
            let a = score(lhs.element), b = score(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a > b
        }.prefix(limit).map(\.element))
    }
}
