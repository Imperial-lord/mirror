import XCTest
@testable import Mirror

@MainActor
final class LibraryDataTests: XCTestCase {
    func testRemovingFavoritesClearsAllFoldersAndSelectingFolderRestoresFavorites() {
        var selection = LibrarySelection(playlists: ["drama", "travel"])
        selection.toggleFavorite()
        XCTAssertFalse(selection.favorite)
        XCTAssertTrue(selection.playlists.isEmpty)
        selection.togglePlaylist("drama")
        XCTAssertTrue(selection.favorite)
        XCTAssertEqual(selection.playlists, ["drama"])
        selection.togglePlaylist("drama")
        XCTAssertTrue(selection.favorite, "Removing a folder keeps the movie in Favorites")
        XCTAssertTrue(selection.playlists.isEmpty)
        selection.toggleFavorite()
        XCTAssertFalse(selection.favorite)
    }
    func testFolderMembershipAlwaysImpliesSavedMovie() {
        XCTAssertTrue(LibrarySelection(favorite: false, playlists: ["folder"]).favorite)
        XCTAssertFalse(LibrarySelection(favorite: false).favorite)
        var selection = LibrarySelection(favorite: false)
        selection.addPlaylist("new-folder")
        XCTAssertTrue(selection.favorite)
        XCTAssertEqual(selection.playlists, ["new-folder"])
    }
    func testLegacySavedMoviePreservesExistingFirestoreData() throws {
        let movie = try XCTUnwrap(SavedMovie(data: ["title": "Saved movie", "year": 2019, "genre": "Drama", "posterURL": "https://example.com/poster.jpg"], documentID: "42"))
        XCTAssertEqual(movie.id, 42)
        XCTAssertEqual(movie.genres, ["Drama"])
        XCTAssertEqual(movie.subtitle, "2019 • Drama")
        XCTAssertEqual(movie.poster, "https://example.com/poster.jpg")
    }
    func testSavedMovieRoundTripKeepsAllGenres() throws {
        let original: [String: Any] = ["id": 42, "title": "Saved movie", "year": 2019, "genres": ["Drama", "Comedy"], "posterURL": "https://example.com/poster.jpg"]
        let movie = try XCTUnwrap(SavedMovie(data: original, documentID: "42"))
        XCTAssertEqual(SavedMovie(data: movie.data, documentID: "42"), movie)
        XCTAssertEqual(movie.genres, ["Drama", "Comedy"])
    }
    func testMalformedMoviesAreNotShownAsUnrelatedCatalogEntries() {
        XCTAssertNil(SavedMovie(data: ["title": "Missing ID"], documentID: "invalid"))
        XCTAssertNil(SavedMovie(data: ["id": 42], documentID: "42"))
    }
    func testPlaylistUsesDocumentIdentityAndAllowsEmptyFolders() throws {
        let playlist = try XCTUnwrap(LibraryPlaylist(id: "firestore-id", data: ["id": "stale-id", "name": "My folder"]))
        XCTAssertEqual(playlist.id, "firestore-id")
        XCTAssertEqual(playlist.movieIds, [])
        XCTAssertNil(LibraryPlaylist(id: "bad", data: [:]))
    }
    func testPlaylistNameValidationTrimsAndRejectsEmptyOrOversizeNames() throws {
        XCTAssertEqual(try LibraryStore.validName("  Film night\n"), "Film night")
        XCTAssertThrowsError(try LibraryStore.validName(" \n "))
        XCTAssertThrowsError(try LibraryStore.validName(String(repeating: "a", count: 61)))
        XCTAssertEqual(try LibraryStore.validName(String(repeating: "a", count: 60)).count, 60)
    }
}
