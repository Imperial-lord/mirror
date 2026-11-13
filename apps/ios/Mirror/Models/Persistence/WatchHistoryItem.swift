import Foundation
import SwiftData

@Model
public final class WatchHistoryItem {
    public var movieId: Int
    public var userId: String = ""
    public var year: Int = 0
    public var genres: [String] = []
    public var backdropURL: String?
    public var durationSeconds: Double = 0
    public var metadataLoaded: Bool = false
    public var title: String
    public var posterURL: String?
    public var runtime: Int // total minutes
    public var progressSeconds: Double // seconds watched
    public var lastWatched: Date

    public init(
        movieId: Int,
        title: String,
        posterURL: String?,
        runtime: Int,
        progressSeconds: Double = 0,
        lastWatched: Date = Date(),
        userId: String = "", year: Int = 0, genres: [String] = [], backdropURL: String? = nil, durationSeconds: Double = 0
    ) {
        self.userId = userId
        self.year = year
        self.genres = genres
        self.backdropURL = backdropURL
        self.durationSeconds = durationSeconds
        self.movieId = movieId
        self.title = title
        self.posterURL = posterURL
        self.runtime = runtime
        self.progressSeconds = progressSeconds
        self.lastWatched = lastWatched
    }

    public var needsMetadata: Bool { year == 0 || (!metadataLoaded && (genres.isEmpty || backdropURL == nil)) }
    public var effectiveDuration: Double { durationSeconds > 0 ? durationSeconds : Double(runtime) * 60 }
    public var progressPercentage: Double {
        guard effectiveDuration.isFinite, effectiveDuration > 0, progressSeconds.isFinite else { return 0 }
        return min(1, max(0, progressSeconds / effectiveDuration))
    }
    public var isWatched: Bool { progressPercentage > 0.95 }
    public var isInProgress: Bool { progressSeconds.isFinite && progressSeconds > 0 && !isWatched }
    public var remainingTime: String {
        guard effectiveDuration.isFinite, progressSeconds.isFinite else { return "0:00:00" }
        let remaining = max(0, Int(effectiveDuration - progressSeconds))
        return String(format: "%d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
    }
    public var subtitle: String {
        [year > 0 ? String(year) : nil, genres.first].compactMap { $0 }.joined(separator: " • ")
    }
}
