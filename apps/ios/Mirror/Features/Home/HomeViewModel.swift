import Foundation
import SwiftUI

@Observable
public final class HomeViewModel {
    public var heroMovies: [Movie] = []
    public var trendingMovies: [Movie] = []
    public var newReleases: [Movie] = []
    public var topRated: [Movie] = []
    public var thrillerMovies: [Movie] = []
    public var selectedForYou: [Movie] = []
    public var genreMovies: [Genre: [Movie]] = [:]
    public var genreErrors: [Genre: String] = [:]
    public var loadingGenres: Set<Genre> = []
    public var collectionRevision = 0
    public var isPersonalizing = false
    public var recommendationError: String?
    private var genreRequests: [Genre: UUID] = [:]
    private var recommendationRequest = UUID()
    public var isLoading: Bool = true
    public var errorMessage: String? = nil

    private let repository: MovieRepositoryProtocol

    public init(repository: MovieRepositoryProtocol = MovieRepository()) {
        self.repository = repository
    }

    @MainActor
    public func loadAll() async {
        isLoading = true
        errorMessage = nil
        genreMovies = [:]
        genreErrors = [:]
        collectionRevision += 1

        async let heroTask = repository.fetchMovies(endpoint: .listMovies(limit: 5, sortBy: "like_count"))
        async let trendingTask = repository.fetchMovies(endpoint: .listMovies(limit: 15, sortBy: "like_count"))
        async let newReleasesTask = repository.fetchMovies(endpoint: .listMovies(limit: 15, sortBy: "date_added"))
        async let topRatedTask = repository.fetchMovies(endpoint: .listMovies(limit: 15, minimumRating: 8, sortBy: "rating"))
        async let actionTask = repository.fetchMovies(endpoint: .listMovies(limit: 15, genre: "Thriller", sortBy: "rating"))

        do {
            let (hero, trending, newRel, top, action) = try await (
                heroTask,
                trendingTask,
                newReleasesTask,
                topRatedTask,
                actionTask
            )

            self.heroMovies = hero
            self.trendingMovies = trending
            self.newReleases = newRel
            self.topRated = top
            self.thrillerMovies = action
            self.genreMovies[.thriller] = action
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isLoading = false
    }
    @MainActor
    public func loadGenre(_ genre: Genre, retry: Bool = false) async {
        guard retry || genreMovies[genre] == nil else { return }
        let request = UUID()
        genreRequests[genre] = request
        loadingGenres.insert(genre)
        genreErrors[genre] = nil
        defer { if genreRequests[genre] == request { loadingGenres.remove(genre) } }
        do {
            let movies = try await repository.fetchMovies(endpoint: .listMovies(limit: 15, genre: genre.rawValue, sortBy: "rating"))
            guard genreRequests[genre] == request else { return }
            genreMovies[genre] = movies
        } catch {
            if genreRequests[genre] == request && !Task.isCancelled { genreErrors[genre] = "Couldn’t load these movies." }
        }
    }

    @MainActor
    func personalize(history: [WatchPreference]) async {
        let request = UUID()
        recommendationRequest = request
        isPersonalizing = true
        recommendationError = nil
        let history = history.filter { $0.progress > 0 }.sorted { $0.lastWatched > $1.lastWatched }
        let seeds = Array(history.prefix(3))
        let preferred = Array(WatchPreferences.rankedGenres(history).prefix(3))
        var candidates: [Movie] = []
        var failures = 0
        // The small group is bounded to six requests. APIClient supplies the shared TTL cache.
        let groups = await withTaskGroup(of: (Int, [Movie]?).self, returning: [(Int, [Movie]?)].self) { group in
            for (index, seed) in seeds.enumerated() {
                group.addTask { [repository] in (index, try? await repository.fetchSuggestions(movieId: seed.movieId)) }
            }
            for (index, genre) in preferred.enumerated() {
                group.addTask { [repository] in
                    (index + 3, try? await repository.fetchMovies(endpoint: .listMovies(limit: 20, genre: genre, sortBy: "rating")))
                }
            }
            var values: [(Int, [Movie]?)] = []
            for await result in group { values.append(result) }
            return values.sorted { $0.0 < $1.0 }
        }
        guard recommendationRequest == request else { return }
        for (_, movies) in groups {
            if let movies { candidates += movies } else { failures += 1 }
        }
        // Cold-start fallback and backfill use current catalog records, never sample titles.
        candidates += newReleases + trendingMovies + topRated
        selectedForYou = WatchPreferences.recommend(candidates: candidates, history: history)
        if !groups.isEmpty && failures == groups.count { recommendationError = "Couldn’t refresh your recommendations." }
        isPersonalizing = false
    }

}
