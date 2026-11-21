import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import XCTest

@testable import MirrorDesktop

/// Local Firebase emulators only; no production account or document is modified.
@MainActor final class HistoryRemovalIntegrationTests: XCTestCase {
  func testDeletionErasesServerAndSDKCacheAndEnrichmentCannotRecreateIt() async throws {
    let options = FirebaseOptions(
      googleAppID: "1:123456789:ios:1234567890abcdef", gcmSenderID: "123456789")
    options.apiKey = "emulator-api-key"
    options.projectID = "demo-mirror-auth"
    let name = "History-\(UUID().uuidString)"
    FirebaseApp.configure(name: name, options: options)
    let app = try XCTUnwrap(FirebaseApp.app(name: name))
    let auth = Auth.auth(app: app)
    auth.useEmulator(withHost: "127.0.0.1", port: 9099)
    let db = Firestore.firestore(app: app)
    let settings = db.settings
    settings.host = "127.0.0.1:8080"
    settings.isSSLEnabled = false
    settings.cacheSettings = MemoryCacheSettings()
    db.settings = settings
    let account = try await auth.createUser(
      withEmail: "history-\(UUID().uuidString)@example.test", password: UUID().uuidString + "aA1!")
    defer { try? auth.signOut() }
    let uid = account.user.uid
    let service = FirestoreService(db: db, account: { auth.currentUser?.uid })
    let user = db.collection("users").document(uid)
    let ref = user.collection("continue_watching").document("123")
    let favorite = user.collection("favorites").document("123")
    let playlist = user.collection("playlists").document("fixture")
    try await ref.setData([
      "movieId": 123, "title": "Fixture", "positionSeconds": 60, "durationSeconds": 600,
      "updatedAt": FieldValue.serverTimestamp(),
    ])
    try await playlist.setData(["name": "Fixture playlist", "movieIds": [456]])
    let movie = SavedMovie(id: 123, title: "Fixture", year: 2020, genres: ["Drama"], poster: "")
    try await LibraryStore.addFavorite(movie, to: user)
    let originalFavorite = try await favorite.getDocument(source: .server)
    try await LibraryStore.addFavorite(movie, to: user)
    let repeatedFavorite = try await favorite.getDocument(source: .server)
    let unchangedPlaylist = try await playlist.getDocument(source: .server)
    XCTAssertEqual(originalFavorite.get("addedAt") as? Timestamp, repeatedFavorite.get("addedAt") as? Timestamp)
    XCTAssertEqual(unchangedPlaylist.get("movieIds") as? [Int], [456])
    let cachedBefore = try await ref.getDocument(source: .cache)
    XCTAssertTrue(cachedBefore.exists)
    do {
      try await service.deleteWatchHistory(movieId: 123, userId: "another-account")
      XCTFail("Must reject an account mismatch")
    } catch {}
    try await service.deleteWatchHistory(movieId: 123, userId: uid)
    await service.enrichWatchHistory(
      movieId: 123, year: 2020, genres: ["Drama"], posterURL: nil, backdropURL: nil, watched: true)
    let server = try await ref.getDocument(source: .server)
    let cache = try await ref.getDocument(source: .cache)
    let saved = try await favorite.getDocument(source: .server)
    XCTAssertFalse(server.exists)
    XCTAssertFalse(cache.exists)
    XCTAssertTrue(saved.exists, "History removal must not remove Favorites")
    let history = try await service.watchHistorySnapshot()
    XCTAssertTrue(history.rows.isEmpty)
    XCTAssertTrue(history.authoritative)
  }
}
