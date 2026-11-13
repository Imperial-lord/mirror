import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SavedMovie: Identifiable, Hashable {
    let id: Int
    let title: String
    let year: Int
    let genres: [String]
    let poster: String

    init(movie: MovieDetail) {
        id = movie.id; title = movie.title; year = movie.year
        genres = movie.genres ?? []; poster = movie.posterURL?.absoluteString ?? ""
    }
    init?(data: [String: Any], documentID: String) {
        guard let id = data["id"] as? Int ?? Int(documentID), let title = data["title"] as? String else { return nil }
        self.id = id; self.title = title; year = data["year"] as? Int ?? 0
        genres = data["genres"] as? [String] ?? (data["genre"] as? String).map { [$0] } ?? []
        poster = data["posterURL"] as? String ?? ""
    }
    var data: [String: Any] { ["id": id, "title": title, "year": year, "genres": genres, "posterURL": poster] }
    var subtitle: String { ([year > 0 ? String(year) : nil, genres.first].compactMap { $0 }).joined(separator: " • ") }
}

struct LibraryPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let movieIds: [Int]
    init(id: String, name: String, movieIds: [Int]) { self.id = id; self.name = name; self.movieIds = movieIds }
    init?(id: String, data: [String: Any]) {
        guard let name = data["name"] as? String else { return nil }
        self.init(id: id, name: name, movieIds: data["movieIds"] as? [Int] ?? [])
    }
}

// A folder is always a subset of Favorites. Deselecting Favorites clears all folders.
struct LibrarySelection {
    private(set) var favorite = true
    private(set) var playlists: Set<String> = []
    init(favorite: Bool = true, playlists: Set<String> = []) {
        self.favorite = favorite || !playlists.isEmpty; self.playlists = playlists
    }
    mutating func toggleFavorite() {
        favorite.toggle()
        if !favorite { playlists = [] }
    }
    mutating func togglePlaylist(_ id: String) {
        if playlists.contains(id) { playlists.remove(id) }
        else { playlists.insert(id); favorite = true }
    }
    mutating func addPlaylist(_ id: String) { playlists.insert(id); favorite = true }
}

@MainActor @Observable
final class LibraryStore {
    static let shared = LibraryStore()
    private(set) var favorites: [SavedMovie] = []
    private(set) var playlists: [LibraryPlaylist] = []
    private(set) var loaded = false
    var error: String?
    private var uid: String?
    var accountID: String? { uid }
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var listeners: [ListenerRegistration] = []
    private var received: Set<String> = []
    private var db: Firestore { Firestore.firestore() }

    func start() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.observe(userId: user?.uid) }
        }
    }
    func retry() { observe(userId: Auth.auth().currentUser?.uid) }
    private func observe(userId: String?) {
        listeners.forEach { $0.remove() }; listeners = []
        uid = userId; favorites = []; playlists = []; received = []; loaded = false; error = nil
        guard let userId else { loaded = true; error = "Sign in to save movies and playlists."; return }
        let user = db.collection("users").document(userId)
        for collection in ["favorites", "playlists"] {
            listeners.append(user.collection(collection).order(by: collection == "favorites" ? "addedAt" : "createdAt", descending: collection == "favorites").addSnapshotListener { [weak self] snapshot, failure in
                Task { @MainActor in
                    guard let self, self.uid == userId else { return }
                    if failure != nil { self.error = "Couldn’t load your library. Please try again."; return }
                    guard let snapshot else { return }
                    if collection == "favorites" {
                        self.favorites = snapshot.documents.compactMap { SavedMovie(data: $0.data(), documentID: $0.documentID) }
                    } else {
                        self.playlists = snapshot.documents.compactMap { LibraryPlaylist(id: $0.documentID, data: $0.data()) }
                    }
                    self.received.insert(collection); self.loaded = self.received.count == 2
                }
            })
        }
        Task {
            do {
                // Seed the existing folder suggestions once, without bringing deleted folders back.
                _ = try await db.runTransaction { transaction, pointer in
                    do {
                        let snapshot = try transaction.getDocument(user)
                        guard snapshot.data()?["libraryDefaultsInitialized"] as? Bool != true else { return nil }
                        for (id, name) in [("default-must-watch", "Must-Watch"), ("default-recommendation", "Recommendation"), ("default-travel", "For traveling")] {
                            transaction.setData(["name": name, "movieIds": [Int](), "createdAt": FieldValue.serverTimestamp()], forDocument: user.collection("playlists").document(id))
                        }
                        transaction.setData(["libraryDefaultsInitialized": true], forDocument: user, merge: true)
                    } catch let failure as NSError { pointer?.pointee = failure }
                    return nil
                }
            } catch { if uid == userId { self.error = "Couldn’t prepare your playlists. Please try again." } }
        }
    }
    private func user() throws -> DocumentReference {
        guard let uid, uid == Auth.auth().currentUser?.uid else { throw LibraryError.signedOut }
        return db.collection("users").document(uid)
    }
    func movies(playlistID: String?) -> [SavedMovie] {
        guard let playlistID else { return favorites }
        let ids = Set(playlists.first { $0.id == playlistID }?.movieIds ?? [])
        return favorites.filter { ids.contains($0.id) }
    }
    func memberships(movieID: Int) -> Set<String> { Set(playlists.filter { $0.movieIds.contains(movieID) }.map(\.id)) }
    static func validName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 60 else { throw LibraryError.invalidName }
        return value
    }
    func create(name: String) async throws -> String {
        let name = try Self.validName(name), ref = try user().collection("playlists").document()
        try await ref.setData(["name": name, "movieIds": [Int](), "createdAt": FieldValue.serverTimestamp()])
        return ref.documentID
    }
    func rename(id: String, name: String) async throws {
        let name = try Self.validName(name)
        try await user().collection("playlists").document(id).updateData(["name": name])
    }
    func delete(id: String) async throws { try await user().collection("playlists").document(id).delete() }
    func save(movie: SavedMovie, favorite: Bool, selections: Set<String>) async throws {
        let user = try user(), batch = db.batch()
        let shouldSave = favorite || !selections.isEmpty
        let ref = user.collection("favorites").document(String(movie.id))
        if shouldSave {
            var data = movie.data
            if !favorites.contains(where: { $0.id == movie.id }) { data["addedAt"] = FieldValue.serverTimestamp() }
            batch.setData(data, forDocument: ref, merge: true)
        } else { batch.deleteDocument(ref) }
        for playlist in playlists {
            let selected = shouldSave && selections.contains(playlist.id)
            if selected != playlist.movieIds.contains(movie.id) {
                batch.updateData(["movieIds": selected ? FieldValue.arrayUnion([movie.id]) : FieldValue.arrayRemove([movie.id])], forDocument: user.collection("playlists").document(playlist.id))
            }
        }
        try await batch.commit()
    }
    func setMovies(playlistID: String, movieIDs: Set<Int>) async throws {
        let ref = try user().collection("playlists").document(playlistID)
        let saved = Set(favorites.map(\.id))
        try await ref.updateData(["movieIds": Array(movieIDs.intersection(saved)).sorted()])
    }
    func remove(movie: SavedMovie, from playlistID: String?) async throws {
        if let playlistID {
            try await user().collection("playlists").document(playlistID).updateData(["movieIds": FieldValue.arrayRemove([movie.id])])
        } else { try await save(movie: movie, favorite: false, selections: []) }
    }
    enum LibraryError: LocalizedError {
        case signedOut, invalidName
        var errorDescription: String? {
            switch self {
            case .signedOut: return "Sign in to manage your library."
            case .invalidName: return "Use a playlist name between 1 and 60 characters."
            }
        }
    }
}
