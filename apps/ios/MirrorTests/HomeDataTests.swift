import XCTest
import UIKit
@testable import Mirror

@MainActor
final class HomeDataTests: XCTestCase {
    func testLandscapeCardsUseLargeStillsInsteadOfBlurredYTSBackgrounds() throws {
        let movie = try artworkMovie([
            "background_image_original": "https://yts.gg/assets/images/movies/a_movie/background.jpg",
            "large_cover_image": "https://yts.gg/assets/images/movies/a_movie/large-cover.jpg"
        ])
        XCTAssertEqual(movie.landscapeStillURL?.absoluteString,
                       "https://img.yts.gg/assets/images/movies/a_movie/large-screenshot1.jpg")
        XCTAssertEqual(movie.posterURL?.lastPathComponent, "large-cover.jpg")
    }

    func testLandscapeArtworkKeepsCustomImagesAndSupportsMissingBackgrounds() throws {
        let custom = try artworkMovie(["background_image": "https://example.test/backdrop.jpg"])
        XCTAssertEqual(custom.landscapeStillURL?.absoluteString, "https://example.test/backdrop.jpg")
        let posterOnly = try artworkMovie(["large_cover_image": "https://example.test/poster.jpg"])
        XCTAssertNil(posterOnly.landscapeStillURL)
        XCTAssertNotNil(posterOnly.posterURL)
    }

    private func artworkMovie(_ artwork: [String: String]) throws -> Movie {
        var fields: [String: Any] = ["id": 1, "url": "https://example.test/movie",
            "imdb_code": "tt1", "title": "Movie", "year": 2026, "rating": 8, "runtime": 120]
        artwork.forEach { fields[$0.key] = $0.value }
        return try JSONDecoder().decode(Movie.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    func testCollectionsUseTheirOwnQueries() async {
        let model = HomeViewModel(repository: HomeFixtureRepository())
        await model.loadAll()
        XCTAssertEqual(model.heroMovies.first?.title, "like_count")
        XCTAssertEqual(model.trendingMovies.first?.title, "like_count")
        XCTAssertEqual(model.newReleases.first?.title, "date_added")
        XCTAssertEqual(model.topRated.first?.title, "rating")
        XCTAssertEqual(model.thrillerMovies.first?.title, "Thriller")
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }
    func testFailureStopsLoadingAndReportsError() async {
        let model = HomeViewModel(repository: HomeFixtureRepository(fails: true))
        await model.loadAll()
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.heroMovies.isEmpty)
    }
}

private struct HomeFixtureRepository: MovieRepositoryProtocol {
    var fails = false
    func fetchMovies(endpoint: APIEndpoint) async throws -> [Movie] {
        if fails { throw APIError.invalidResponse }
        let label = endpoint.queryItems.first { $0.name == "genre" }?.value
            ?? endpoint.queryItems.first { $0.name == "sort_by" }?.value ?? "unknown"
        let data = try JSONSerialization.data(withJSONObject: ["id":1,"url":"https://example.test/movie","imdb_code":"tt1","title":label,"year":2026,"rating":8.5,"runtime":120])
        return [try JSONDecoder().decode(Movie.self, from: data)]
    }
    func fetchMovieDetail(id: Int) async throws -> MovieDetail { throw APIError.invalidResponse }
    func fetchSuggestions(movieId: Int) async throws -> [Movie] { [] }
}

@MainActor
final class CatalogDataTests: XCTestCase {
    func testFiltersWorkWithoutSearchText() async {
        let model = SearchViewModel(repository: CatalogFixtureRepository())
        model.selectedGenre = "Thriller"
        model.minimumRating = 8
        model.sortBy = "rating"
        await model.performSearch()
        XCTAssertEqual(model.searchResults.first?.title, "Thriller|8|rating|")
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.errorMessage)
    }

    func testEmptyFilteredCatalogDoesNotFallBackToPopularMovies() async {
        let model = SearchViewModel(repository: CatalogFixtureRepository(empty: true))
        model.selectedGenre = "Horror"
        await model.performSearch()
        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    func testPaginationAdvancesPageAndDeduplicatesMovieIDs() async {
        let model = SearchViewModel(repository: CatalogFixtureRepository())
        await model.performSearch()
        XCTAssertEqual(model.searchResults.count, 30)
        await model.loadNextPage()
        XCTAssertEqual(model.searchResults.count, 59)
        XCTAssertEqual(model.searchResults.last?.id, 59)
        XCTAssertFalse(model.isSearching)
    }

    func testPartialTitleFallbackKeepsFiltersAndUsesTheBroaderQueryForPagination() async {
        let model = SearchViewModel(repository: CatalogFixtureRepository(partialSearch: true))
        model.query = "monsters uni"
        model.selectedGenre = "Comedy"
        model.minimumRating = 7
        model.sortBy = "rating"

        await model.performSearch()
        XCTAssertEqual(model.searchResults.map(\.title), ["Monsters University"])
        XCTAssertTrue(model.canLoadMore)

        await model.loadNextPage()
        XCTAssertEqual(model.searchResults.map(\.title), ["Monsters University", "Mónsters: United"])
        XCTAssertFalse(model.canLoadMore)
        XCTAssertNil(model.errorMessage)
    }

    func testNetworkErrorIsDistinctFromNoMatches() async {
        let model = SearchViewModel(repository: CatalogFixtureRepository(fails: true))
        await model.performSearch()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isEmpty)
        XCTAssertFalse(model.isSearching)
    }
}

private struct CatalogFixtureRepository: MovieRepositoryProtocol {
    var empty = false
    var fails = false
    var partialSearch = false
    func fetchMovies(endpoint: APIEndpoint) async throws -> [Movie] {
        if fails { throw APIError.invalidResponse }
        if empty { return [] }
        let values = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })
        let page = Int(values["page"] ?? "1") ?? 1
        let start = page == 1 ? 1 : 30
        let titles: [String]
        if partialSearch {
            guard values["query_term"] == "monsters", values["genre"] == "Comedy",
                  values["minimum_rating"] == "7", values["sort_by"] == "rating" else { return [] }
            titles = page == 1 ? ["Monsters University"] + Array(repeating: "Monsters, Inc.", count: 29) : ["Mónsters: United"]
        } else {
            let label = [values["genre"] ?? "", values["minimum_rating"] ?? "", values["sort_by"] ?? "", values["query_term"] ?? ""].joined(separator: "|")
            titles = Array(repeating: label, count: 30)
        }
        return try titles.enumerated().map { offset, title in
            let id = start + offset
            let data = try JSONSerialization.data(withJSONObject: ["id":id,"url":"https://example.test/movie","imdb_code":"tt\(id)","title":title,"year":2026,"rating":8.5,"runtime":120])
            return try JSONDecoder().decode(Movie.self, from: data)
        }
    }
    func fetchMovieDetail(id: Int) async throws -> MovieDetail { throw APIError.invalidResponse }
    func fetchSuggestions(movieId: Int) async throws -> [Movie] { [] }
}

@MainActor
final class PhosphorAssetTests: XCTestCase {
    func testEveryIconLoadsAndRendersVisiblePixels() throws {
        for icon in PhosphorIcon.allCases {
            let image = try XCTUnwrap(UIImage(named: icon.assetName), "Missing icon: \(icon.assetName)")
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { _ in
                image.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            let cgImage = try XCTUnwrap(rendered.cgImage)
            let bytes = try XCTUnwrap(cgImage.dataProvider?.data) as Data
            XCTAssertTrue(bytes.contains { $0 != 0 }, "Blank icon: \(icon.assetName)")
        }
    }
}

final class SubtitleParsingTests: XCTestCase {
    func testParsesTimedMultilineUnicodeCaptionsAndStripsMarkup() {
        let cues = SubtitleParser.parse("1\r\n00:01:02,500 --> 00:01:05,000\r\n<i>Bonjour &amp; ciao</i>\r\nEspañol\r\n\r\n2\r\n00:02:00,000 --> 00:02:02,000\r\nNext")
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 62.5)
        XCTAssertEqual(cues[0].end, 65)
        XCTAssertEqual(cues[0].text, "Bonjour & ciao\nEspañol")
    }
    func testDiscardsInvalidAndReversedTiming() {
        XCTAssertTrue(SubtitleParser.parse("1\n00:61:00,000 --> 00:62:00,000\nInvalid\n\n2\n00:00:05,000 --> 00:00:01,000\nReversed").isEmpty)
    }
}

@MainActor
final class ProductionFilterTests: XCTestCase {
    func testCountryStudioAndYearAreCombinedAndSkipNonmatchingFirstPage() async {
        let model = SearchViewModel(repository: ProductionFixtureRepository(), metadata: ProductionFixtureMetadata())
        model.selectedCountry = "Q30"
        model.selectedStudio = "Q367466"
        model.selectedYear = 2019
        await model.performSearch()
        XCTAssertEqual(model.searchResults.map(\.id), [31])
        XCTAssertFalse(model.canLoadMore)
        XCTAssertFalse(model.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testEmptyFilteredBatchKeepsPaginationUntilSourceIsExhausted() async {
        let model = SearchViewModel(repository: ProductionFixtureRepository(long: true), metadata: ProductionFixtureMetadata())
        model.selectedCountry = "Q668"
        await model.performSearch()
        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertTrue(model.canLoadMore)
        XCTAssertFalse(model.isEmpty, "An empty batch must not report no catalog matches")
        await model.loadNextPage()
        XCTAssertEqual(model.searchResults.count, 30)
        XCTAssertEqual(model.searchResults.first?.id, 181)
        await model.loadNextPage()
        XCTAssertFalse(model.canLoadMore)
    }

    func testMetadataFailureIsAnErrorAndRetryDoesNotSkipThePage() async {
        let metadata = FailingOnceProductionMetadata()
        let model = SearchViewModel(repository: ProductionFixtureRepository(), metadata: metadata)
        model.selectedCountry = "Q30"
        await model.performSearch()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isEmpty)
        await model.performSearch()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.searchResults.first?.id, 1)
    }
}

private struct ProductionFixtureRepository: MovieRepositoryProtocol {
    var long = false
    func fetchMovies(endpoint: APIEndpoint) async throws -> [Movie] {
        let page = Int(endpoint.queryItems.first { $0.name == "page" }?.value ?? "1") ?? 1
        let count = long ? (page <= 7 ? 30 : 0) : (page == 1 ? 30 : page == 2 ? 3 : 0)
        return try (0..<count).map { offset in
            let id = (page - 1) * 30 + offset + 1
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "url":"https://example.test/movie", "imdb_code": "tt\(id)", "title":"Fixture \(id)", "year":page == 1 ? 2020 : 2019, "rating":8, "runtime":120])
            return try JSONDecoder().decode(Movie.self, from: data)
        }
    }
    func fetchMovieDetail(id: Int) async throws -> MovieDetail { throw APIError.invalidResponse }
    func fetchSuggestions(movieId: Int) async throws -> [Movie] { [] }
}

private struct ProductionFixtureMetadata: CatalogMetadataProviding {
    func production(for movies: [Movie]) async throws -> [String: CatalogProduction] {
        Dictionary(uniqueKeysWithValues: movies.map { movie in
            (movie.imdbCode, CatalogProduction(countries: [movie.id >= 181 ? "Q668" : movie.id == 32 ? "Q145" : "Q30"], studios: [movie.id == 33 ? "Q168383" : "Q367466"]))
        })
    }
}

private actor FailingOnceProductionMetadata: CatalogMetadataProviding {
    private var failed = false
    func production(for movies: [Movie]) async throws -> [String: CatalogProduction] {
        if !failed { failed = true; throw URLError(.timedOut) }
        return try await ProductionFixtureMetadata().production(for: movies)
    }
}

final class PeopleIdentityTests: XCTestCase {
    func testLegacyCastDecodesAndNormalizesIMDbIdentity() throws {
        let bytes = Data(#"{"name":"John Hurt","character_name":"The Doctor","imdb_code":"0000457","url_small_image":null}"#.utf8)
        let person = try JSONDecoder().decode(Cast.self, from: bytes)
        XCTAssertEqual(person.normalizedIMDbID, "nm0000457")
        XCTAssertEqual(person.creditRole, "Actor")
        XCTAssertEqual(person.characterName, "The Doctor")
    }

    func testOMDbNamesDoNotInventPersonIDs() throws {
        let bytes = Data(#"{"name":"Nick Hurran","department":"Director"}"#.utf8)
        let person = try JSONDecoder().decode(Cast.self, from: bytes)
        XCTAssertNil(person.normalizedIMDbID)
        XCTAssertEqual(person.creditRole, "Director")
        XCTAssertNil(person.avatarURL)
    }

    func testSamePersonCanHaveDistinctActorAndDirectorCredits() {
        let actor = Cast(name: "Person", characterName: nil, urlSmallImage: nil, imdbCode: "nm0000001")
        var director = actor
        director.department = "Director"
        XCTAssertNotEqual(actor.id, director.id)
        XCTAssertEqual(actor.normalizedIMDbID, director.normalizedIMDbID)
    }
}
