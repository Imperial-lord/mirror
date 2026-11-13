import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
enum WatchHistorySync {
    static func sync(context: ModelContext, repository: MovieRepositoryProtocol = MovieRepository.shared) async -> String? {
        guard let uid = AuthService.shared.currentUser?.uid else { return nil }
        do {
            let rows = try await FirestoreService.shared.fetchWatchHistory()
            guard AuthService.shared.currentUser?.uid == uid else { return nil }
            let all = try merge(rows: rows, userId: uid, context: context)
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
                guard AuthService.shared.currentUser?.uid == uid else { return nil }
                if details.count < ids.count { failedDetails = true }
                for movie in details {
                    guard AuthService.shared.currentUser?.uid == uid else { return nil }
                    guard let item = all.first(where: { $0.movieId == movie.id && $0.userId == uid }) else { continue }
                    item.metadataLoaded = true
                    item.year = movie.year
                    item.genres = movie.genres ?? []
                    item.posterURL = movie.posterURL?.absoluteString
                    item.backdropURL = movie.backdropURL?.absoluteString
                    await FirestoreService.shared.enrichWatchHistory(movieId: movie.id, year: item.year, genres: item.genres,
                        posterURL: item.posterURL, backdropURL: item.backdropURL, watched: item.isWatched)
                }
            }
            try context.save()
            return failedDetails ? "Some movie details couldn’t load. Pull to refresh to try again." : nil
        } catch { return "Couldn’t refresh your watch history. Pull to refresh to try again." }
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
