import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

@MainActor
public final class FirestoreService {
    public static let shared = FirestoreService()

    private lazy var db: Firestore = {
        return Firestore.firestore()
    }()

    private init() {}

    // MARK: - App User ID
    public var currentUserId: String {
        if let authUid = Auth.auth().currentUser?.uid {
            return authUid
        }
        if let savedId = UserDefaults.standard.string(forKey: "mirror_user_id") {
            return savedId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "mirror_user_id")
        return newId
    }

    // MARK: - Continue Watching
    public func savePlaybackProgress(
        movieId: Int,
        title: String,
        posterURL: String?,
        positionSeconds: Double,
        durationSeconds: Double,
        year: Int = 0, genres: [String] = [], backdropURL: String? = nil
    ) {
        guard positionSeconds.isFinite, durationSeconds.isFinite, positionSeconds >= 0, durationSeconds > 0 else { return }
        let docRef = db.collection("users").document(currentUserId)
            .collection("continue_watching").document("\(movieId)")

        let data: [String: Any] = [
            "movieId": movieId,
            "year": year,
            "genres": genres,
            "backdropURL": backdropURL ?? "",
            "watched": durationSeconds > 0 && positionSeconds / durationSeconds > 0.95,
            "title": title,
            "posterURL": posterURL ?? "",
            "positionSeconds": positionSeconds,
            "durationSeconds": durationSeconds,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        docRef.setData(data, merge: true)
    }

    public func playbackPosition(movieId: Int) async throws -> Double? {
        try await playbackCheckpoint(movieId: movieId)?.position
    }

    func playbackCheckpoint(movieId: Int) async throws -> (position: Double, updatedAt: Date)? {
        let snapshot = try await db.collection("users").document(currentUserId)
            .collection("continue_watching").document(String(movieId)).getDocument()
        guard let data = snapshot.data(), let value = data["positionSeconds"] as? Double,
              value.isFinite, value >= 0 else { return nil }
        return (value, (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast)
    }

    public func fetchWatchHistory() async throws -> [[String: Any]] {
        let snapshot = try await db.collection("users").document(currentUserId)
            .collection("continue_watching").order(by: "updatedAt", descending: true).getDocuments()
        return snapshot.documents.map { $0.data() }
    }

    public func enrichWatchHistory(movieId: Int, year: Int, genres: [String], posterURL: String?, backdropURL: String?, watched: Bool) async {
        try? await db.collection("users").document(currentUserId).collection("continue_watching")
            .document(String(movieId)).setData(["year": year, "genres": genres,
                "posterURL": posterURL ?? "", "backdropURL": backdropURL ?? "", "watched": watched], merge: true)
    }

    public func fetchContinueWatching() async -> [[String: Any]] {
        let colRef = db.collection("users").document(currentUserId)
            .collection("continue_watching")
            .order(by: "updatedAt", descending: true)
            .limit(to: 10)

        do {
            let snapshot = try await colRef.getDocuments()
            return snapshot.documents.map { $0.data() }
        } catch {
            return []
        }
    }

    // MARK: - Favorites & Watchlist
    public func toggleFavorite(movie: Movie, isFavorite: Bool) async {
        let docRef = db.collection("users").document(currentUserId)
            .collection("favorites").document("\(movie.id)")

        if isFavorite {
            let data: [String: Any] = [
                "id": movie.id,
                "title": movie.title,
                "year": movie.year,
                "rating": movie.rating,
                "posterURL": movie.posterURL?.absoluteString ?? "",
                "genre": movie.genres?.first ?? "Movie",
                "addedAt": FieldValue.serverTimestamp()
            ]
            try? await docRef.setData(data)
        } else {
            try? await docRef.delete()
        }
    }

    public func fetchFavorites() async -> [[String: Any]] {
        let colRef = db.collection("users").document(currentUserId)
            .collection("favorites")
            .order(by: "addedAt", descending: true)

        do {
            let snapshot = try await colRef.getDocuments()
            return snapshot.documents.map { $0.data() }
        } catch {
            return []
        }
    }

    // MARK: - Playlists
    public func createPlaylist(name: String) async {
        let docRef = db.collection("users").document(currentUserId)
            .collection("playlists").document()

        let data: [String: Any] = [
            "id": docRef.documentID,
            "name": name,
            "movieIds": [Int](),
            "createdAt": FieldValue.serverTimestamp()
        ]

        try? await docRef.setData(data)
    }

    public func fetchPlaylists() async -> [[String: Any]] {
        let colRef = db.collection("users").document(currentUserId)
            .collection("playlists")
            .order(by: "createdAt", descending: false)

        do {
            let snapshot = try await colRef.getDocuments()
            return snapshot.documents.map { $0.data() }
        } catch {
            return []
        }
    }

    // MARK: - Reviews & Ratings
    public func submitReview(
        movieId: Int,
        movieTitle: String,
        rating: Int,
        headline: String,
        content: String,
        author: String = "User"
    ) async {
        let docRef = db.collection("reviews").document()
        let data: [String: Any] = [
            "movieId": movieId,
            "movieTitle": movieTitle,
            "rating": rating,
            "headline": headline,
            "content": content,
            "authorName": author,
            "userId": currentUserId,
            "createdAt": FieldValue.serverTimestamp()
        ]
        try? await docRef.setData(data)
    }
}
