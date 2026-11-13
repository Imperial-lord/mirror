import XCTest
import SwiftData
import FirebaseFirestore
@testable import Mirror

@MainActor
final class WatchHistoryTests: XCTestCase {
    func testCompletionUsesExactDurationAndStrictlyMoreThan95Percent() {
        let item = WatchHistoryItem(movieId: 1, title: "Movie", posterURL: nil, runtime: 17,
                                    progressSeconds: 950, durationSeconds: 1000)
        XCTAssertEqual(item.progressPercentage, 0.95)
        XCTAssertFalse(item.isWatched)
        XCTAssertTrue(item.isInProgress)
        item.progressSeconds = 950.1
        XCTAssertTrue(item.isWatched)
        XCTAssertFalse(item.isInProgress)
        item.progressSeconds = 2000
        XCTAssertEqual(item.progressPercentage, 1)
        item.progressSeconds = 0
        XCTAssertFalse(item.isWatched)
        XCTAssertFalse(item.isInProgress)
    }

    func testLegacyDurationFallbackAndUnknownDuration() {
        let item = WatchHistoryItem(movieId: 1, title: "Movie", posterURL: nil, runtime: 10, progressSeconds: 580)
        XCTAssertTrue(item.isWatched)
        item.runtime = 0
        XCTAssertFalse(item.isWatched)
        item.progressSeconds = .nan
        XCTAssertEqual(item.progressPercentage, 0)
    }

    func testSameMovieHistoryCanPersistSeparatelyForTwoAccounts() throws {
        let container = try ModelContainer(for: WatchHistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(WatchHistoryItem(movieId: 1, title: "Movie", posterURL: nil, runtime: 10, progressSeconds: 580, userId: "one"))
        context.insert(WatchHistoryItem(movieId: 1, title: "Movie", posterURL: nil, runtime: 10, progressSeconds: 100, userId: "two"))
        try context.save()
        let rows = try context.fetch(FetchDescriptor<WatchHistoryItem>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.userId == "one" }).isWatched)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.userId == "two" }).isInProgress)
    }

    func testCloudMigrationKeepsMissingMetadataEligibleForEnrichment() throws {
        let container = try ModelContainer(for: WatchHistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let item = WatchHistoryItem(movieId: 1, title: "Old", posterURL: nil, runtime: 17, progressSeconds: 10,
                                    lastWatched: Date().addingTimeInterval(60))
        context.insert(item)
        let rows: [[String: Any]] = [["movieId": 1, "title": "Movie", "positionSeconds": 950.0,
            "durationSeconds": 1000.0, "updatedAt": Timestamp(date: Date())]]
        let merged = try WatchHistorySync.merge(rows: rows, userId: "one", context: context)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(item.userId, "one")
        XCTAssertEqual(item.progressSeconds, 950)
        XCTAssertEqual(item.durationSeconds, 1000)
        XCTAssertFalse(item.isWatched)
        XCTAssertTrue(item.needsMetadata)
        item.progressSeconds = 800
        item.lastWatched = Date().addingTimeInterval(60)
        _ = try WatchHistorySync.merge(rows: rows, userId: "one", context: context)
        XCTAssertEqual(item.progressSeconds, 800, "Newer owned local progress must survive an older cloud response")
        item.metadataLoaded = true // Also repair the intermediate missing-year case.
        XCTAssertTrue(item.needsMetadata)
        item.year = 2020
        XCTAssertFalse(item.needsMetadata)
    }

    func testLibraryGenresComeOnlyFromCompletedMovies() {
        let completed = WatchHistoryItem(movieId: 1, title: "Finished", posterURL: nil, runtime: 10,
            progressSeconds: 580, genres: ["Action", "Adventure", "Action"])
        let started = WatchHistoryItem(movieId: 2, title: "Started", posterURL: nil, runtime: 10,
            progressSeconds: 60, genres: ["Horror"])
        XCTAssertEqual(LibraryHistory.genres(in: [completed, started]), ["Action", "Adventure"])
    }

    func testLibraryGenreSelectionFiltersOwnHistoryInsteadOfGeneralCatalog() {
        let action = WatchHistoryItem(movieId: 1, title: "Finished action", posterURL: nil, runtime: 10,
            progressSeconds: 580, genres: ["Action"])
        let drama = WatchHistoryItem(movieId: 2, title: "Finished drama", posterURL: nil, runtime: 10,
            progressSeconds: 580, genres: ["Drama"])
        let started = WatchHistoryItem(movieId: 3, title: "Started action", posterURL: nil, runtime: 10,
            progressSeconds: 60, genres: ["Action"])
        let items = [action, drama, started]
        XCTAssertEqual(LibraryHistory.movies(in: .genre("Action"), from: items).map(\.movieId), [1])
        XCTAssertEqual(LibraryHistory.movies(in: .continuing, from: items).map(\.movieId), [3])
        XCTAssertTrue(LibraryHistory.movies(in: .genre("Horror"), from: items).isEmpty)
    }

    func testRecommendationsUseGenresExcludeHistoryAndDeduplicate() throws {
        let history = [WatchPreference(movieId: 1, genres: ["Horror", "Horror"], progress: 1, lastWatched: Date())]
        let action = try movie(2, genre: "Action"), horror = try movie(3, genre: "Horror"), seen = try movie(1, genre: "Horror")
        let result = WatchPreferences.recommend(candidates: [action, seen, horror, horror], history: history)
        XCTAssertEqual(result.map(\.id), [3, 2])
        XCTAssertEqual(WatchPreferences.rankedGenres(history), ["Horror"])
    }

    func testPersonalizedRequestsUseHistorySeedsAndUnseenSuggestions() async {
        let repository = RecommendationFixtureRepository()
        let model = HomeViewModel(repository: repository)
        await model.loadAll()
        await model.personalize(history: [.init(movieId: 1, genres: ["Horror"], progress: 1, lastWatched: Date())])
        let seeds = await repository.seedIDs
        XCTAssertEqual(seeds, [1])
        XCTAssertEqual(model.selectedForYou.first?.id, 3)
        XCTAssertFalse(model.selectedForYou.contains { $0.id == 1 })
        XCTAssertFalse(model.isPersonalizing)
    }

    func testEveryFilterGenreHasARealBestCollection() async {
        let model = HomeViewModel(repository: RecommendationFixtureRepository())
        for genre in Genre.catalogGenres { await model.loadGenre(genre) }
        XCTAssertEqual(Set(model.genreMovies.keys), Set(Genre.catalogGenres))
        for genre in Genre.catalogGenres { XCTAssertEqual(model.genreMovies[genre]?.first?.genres, [genre.rawValue]) }
    }

    private func movie(_ id: Int, genre: String) throws -> Movie {
        try makeHistoryFixtureMovie(id, genre: genre)
    }
}

private func makeHistoryFixtureMovie(_ id: Int, genre: String) throws -> Movie {
    let data = try JSONSerialization.data(withJSONObject: ["id":id,"url":"https://example.test/movie","imdb_code":"tt1","title":genre,"year":2020,"rating":8,"runtime":100,"genres":[genre]])
    return try JSONDecoder().decode(Movie.self, from: data)
}

private actor RecommendationFixtureRepository: MovieRepositoryProtocol {
    var seedIDs: [Int] = []
    func fetchMovies(endpoint: APIEndpoint) async throws -> [Movie] {
        let genre = endpoint.queryItems.first { $0.name == "genre" }?.value ?? "Drama"
        return [try makeHistoryFixtureMovie(2, genre: genre)]
    }
    func fetchSuggestions(movieId: Int) async throws -> [Movie] {
        seedIDs.append(movieId)
        return [try makeHistoryFixtureMovie(1, genre: "Horror"), try makeHistoryFixtureMovie(3, genre: "Horror")]
    }
    func fetchMovieDetail(id: Int) async throws -> MovieDetail { throw APIError.invalidResponse }
}
