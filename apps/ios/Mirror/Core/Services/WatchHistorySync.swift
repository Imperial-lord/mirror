import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
enum WatchHistorySync {
    private static var revision = 0

    static func sync(context: ModelContext, repository: MovieRepositoryProtocol = MovieRepository.shared,
        account: @MainActor () -> String? = { AuthService.shared.currentUser?.uid },
        fetchHistory: @MainActor (String) async throws -> (rows: [[String: Any]], authoritative: Bool) = { try await FirestoreService.shared.watchHistorySnapshot(userId: $0) }
    ) async -> String? {
        guard let uid = account() else { return nil }
        let startedAt = Date(), version = revision
        do {
            let snapshot = try await fetchHistory(uid)
            guard account() == uid, revision == version else { return nil }
            if snapshot.authoritative {
                try pruneMissing(rows: snapshot.rows, userId: uid, before: startedAt, context: context)
            }
            let all = try merge(rows: snapshot.rows, userId: uid, context: context)
            let missing = all.filter { $0.userId == uid && $0.needsMetadata }
            var failedDetails = false
            for offset in stride(from: 0, to: missing.count, by: 4) {
                let ids = missing[offset..<min(offset + 4, missing.count)].map(\.movieId)
                let details = await withTaskGroup(of: MovieDetail?.self, returning: [MovieDetail].self) { group in
                    for id in ids { group.addTask { try? await repository.fetchMovieDetail(id: id) } }
                    var result: [MovieDetail] = []
                    for await detail in group { if let detail { result.append(detail) } }
                    return result
                }
                guard account() == uid, revision == version else { return nil }
                if details.count < ids.count { failedDetails = true }
                for movie in details {
                    guard account() == uid, revision == version else { return nil }
                    guard let item = all.first(where: { $0.movieId == movie.id && $0.userId == uid }) else { continue }
                    item.metadataLoaded = true
                    item.year = movie.year
                    item.genres = movie.genres ?? []
                    item.posterURL = movie.posterURL?.absoluteString
                    item.backdropURL = movie.backdropURL?.absoluteString
                    await FirestoreService.shared.enrichWatchHistory(movieId: movie.id, year: item.year, genres: item.genres,
                        posterURL: item.posterURL, backdropURL: item.backdropURL, watched: item.isWatched, userId: uid)
                }
            }
            guard revision == version else { return nil }
            try context.save()
            return failedDetails ? "Some movie details couldn’t load. Pull to refresh to try again." : nil
        } catch { return "Couldn’t refresh your watch history. Pull to refresh to try again." }
    }

    static func remove(movieId: Int, userId: String, context: ModelContext,
        deleteRemote: @MainActor (Int, String) async throws -> Void = { try await FirestoreService.shared.deleteWatchHistory(movieId: $0, userId: $1) },
        resetOffline: @MainActor (Int, String) throws -> Void = { try DownloadStore.shared.clearPlayback(id: $0, userId: $1) }
    ) async throws {
        guard movieId > 0, !userId.isEmpty else { throw FirestoreService.HistoryError.accountChanged }
        revision += 1
        defer { revision += 1 }
        try await deleteRemote(movieId, userId)
        try resetOffline(movieId, userId)
        let rows = try context.fetch(FetchDescriptor<WatchHistoryItem>())
        for row in rows where row.movieId == movieId && row.userId == userId { context.delete(row) }
        try context.save()
    }

    // A server-confirmed absence also removes this device's cache after deletion on another device.
    // Preserve progress written while the request was in flight, and never prune from an offline cache.
    static func pruneMissing(rows: [[String: Any]], userId: String, before: Date, context: ModelContext,
        resetOffline: @MainActor (Int, String) throws -> Void = { try DownloadStore.shared.clearPlayback(id: $0, userId: $1) }
    ) throws {
        let remoteIDs = Set(rows.compactMap { $0["movieId"] as? Int })
        let local = try context.fetch(FetchDescriptor<WatchHistoryItem>())
        for item in local where item.userId == userId && !remoteIDs.contains(item.movieId) && item.lastWatched <= before {
            try resetOffline(item.movieId, userId)
            context.delete(item)
        }
        try context.save()
    }

    static func merge(rows: [[String: Any]], userId uid: String, context: ModelContext) throws -> [WatchHistoryItem] {
        var all = try context.fetch(FetchDescriptor<WatchHistoryItem>())
        for row in rows {
            guard let id = row["movieId"] as? Int, let title = row["title"] as? String,
                  let position = row["positionSeconds"] as? Double, position.isFinite, position >= 0,
                  let duration = row["durationSeconds"] as? Double, duration.isFinite, duration > 0 else { continue }
            let date = (row["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            // Legacy local entries are claimed only when this account has the same cloud record.
            let existing = all.first { $0.movieId == id && $0.userId == uid }
                ?? all.first { $0.movieId == id && $0.userId.isEmpty }
            let wasUnscoped = existing?.userId.isEmpty == true
            let item = existing ?? WatchHistoryItem(movieId: id, title: title, posterURL: nil, runtime: 0, userId: uid)
            if existing == nil { context.insert(item); all.append(item) }
            item.userId = uid
            if item.durationSeconds <= 0 { item.durationSeconds = duration }
            if date >= item.lastWatched || existing == nil || wasUnscoped {
                item.title = title
                item.progressSeconds = position
                item.durationSeconds = duration
                item.runtime = max(1, Int(duration / 60))
                item.lastWatched = date
            }
            if item.year == 0 { item.year = row["year"] as? Int ?? 0 }
            if item.genres.isEmpty { item.genres = row["genres"] as? [String] ?? [] }
            if item.posterURL == nil { item.posterURL = row["posterURL"] as? String }
            if item.backdropURL == nil { item.backdropURL = (row["backdropURL"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        }
        try context.save()
        return all
    }

    static func saveLocal(context: ModelContext, movie: MovieDetail, position: Double, duration: Double) {
        guard let uid = AuthService.shared.currentUser?.uid, position.isFinite, position > 0, duration.isFinite, duration > 0 else { return }
        let id = movie.id
        let descriptor = FetchDescriptor<WatchHistoryItem>(predicate: #Predicate { $0.movieId == id && $0.userId == uid })
        let existing = try? context.fetch(descriptor).first
        let item = existing ?? WatchHistoryItem(movieId: id, title: movie.title, posterURL: movie.posterURL?.absoluteString, runtime: movie.runtime, userId: uid)
        if existing == nil { context.insert(item) }
        item.metadataLoaded = true
        item.progressSeconds = position
        item.durationSeconds = duration
        item.runtime = max(1, Int(duration / 60))
        item.lastWatched = Date()
        item.year = movie.year
        item.genres = movie.genres ?? []
        item.posterURL = movie.posterURL?.absoluteString
        item.backdropURL = movie.backdropURL?.absoluteString
        try? context.save()
    }
}
