import SwiftUI
import SwiftData
import NukeUI

enum HistoryCollection: Hashable {
    case continuing, watched, genres, genre(String)
    var title: String {
        switch self {
        case .continuing: return "Continue Watching"
        case .watched: return "Watched"
        case .genres: return "Genres you Watched"
        case .genre(let name): return name
        }
    }
}

enum LibraryHistory {
    static func genres(in items: [WatchHistoryItem]) -> [String] {
        var counts: [String: Int] = [:]
        for item in items where item.isWatched {
            for genre in Set(item.genres) where genre != "All" { counts[genre, default: 0] += 1 }
        }
        return counts.keys.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0]! > counts[$1]! }
    }
    static func movies(in collection: HistoryCollection, from items: [WatchHistoryItem]) -> [WatchHistoryItem] {
        let sorted = items.sorted { $0.lastWatched > $1.lastWatched }
        switch collection {
        case .continuing: return sorted.filter(\.isInProgress)
        case .watched, .genres: return sorted.filter(\.isWatched)
        case .genre(let name): return sorted.filter { $0.isWatched && $0.genres.contains(name) }
        }
    }
}

struct RecentLibraryContent: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var history: [WatchHistoryItem]
    @State private var resume: ResumeMovie?
    @State private var selectedMovie: Int?
    @State private var error: String?
    @State private var isLoading = true

    private var owned: [WatchHistoryItem] { history.filter { $0.userId == AuthService.shared.currentUser?.uid } }
    private var continuing: [WatchHistoryItem] { LibraryHistory.movies(in: .continuing, from: owned) }
    private var watched: [WatchHistoryItem] { LibraryHistory.movies(in: .watched, from: owned) }
    private var genres: [String] { LibraryHistory.genres(in: owned) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if let error { empty(error) }
                if isLoading && owned.isEmpty { ProgressView().tint(Color.mirrorInk).frame(maxWidth: .infinity) }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(.continuing)
                    if continuing.isEmpty { empty("Movies you start will appear here.") }
                    else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.sm) {
                                ForEach(continuing) { historyContinueCard($0) }
                            }.padding(.horizontal, Spacing.md)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(.watched)
                    if watched.isEmpty { empty("Movies appear here after you finish more than 95%.") }
                    else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                ForEach(watched) { item in movieLink(item, width: 125) }
                            }.padding(.horizontal, Spacing.md)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(.genres)
                    if genres.isEmpty { empty("Genres from movies you’ve finished will appear here.") }
                    else {
                        Text("From movies you’ve finished").font(.mirrorCaptionSmall)
                            .foregroundStyle(Color.mirrorTextTertiary).padding(.horizontal, Spacing.md)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(genres, id: \.self) { name in
                                    NavigationLink(value: HistoryCollection.genre(name)) {
                                        Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.mirrorInk)
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, Spacing.md)
                        }
                    }
                }
            }.padding(.bottom, 110)
        }
        .tint(Color.mirrorInk)
        .refreshable { await refresh() }
        .task { await refresh() }
        .fullScreenCover(item: $resume, onDismiss: { Task { await refresh() } }) { item in
            ResumeMoviePlayer(movieId: item.id, position: item.position, requestedAt: item.requestedAt)
        }
        .navigationDestination(for: HistoryCollection.self) { collection in
            HistoryCollectionPage(collection: collection, items: owned,
                onResume: { resume = ResumeMovie(id: $0.movieId, position: $0.progressSeconds) },
                onMore: { selectedMovie = $0.movieId }, onRefresh: { await refresh() })
        }
        .navigationDestination(item: $selectedMovie) { MovieDetailView(movieId: $0) }
    }

    private func sectionHeader(_ collection: HistoryCollection) -> some View {
        NavigationLink(value: collection) {
            HStack {
                Text(collection.title).font(.system(size: 17, weight: .semibold))
                Spacer()
                PhosphorView(.caretRight, size: 12, color: Color.mirrorTextTertiary)
            }.foregroundStyle(Color.mirrorInk).padding(.horizontal, Spacing.md)
        }.buttonStyle(.plain)
    }
    private func empty(_ text: String) -> some View {
        Text(text).font(.mirrorBodySmall).foregroundStyle(Color.mirrorTextTertiary).padding(.horizontal, Spacing.md)
    }
    private func historyContinueCard(_ item: WatchHistoryItem) -> some View {
        ContinueWatchingCard(title: item.title, subtitle: item.subtitle,
            imageURL: URL(string: item.backdropURL ?? item.posterURL ?? ""), timeRemaining: item.remainingTime,
            progress: item.progressPercentage, onResume: { resume = ResumeMovie(id: item.movieId, position: item.progressSeconds) },
            onMore: { selectedMovie = item.movieId })
    }
    private func movieLink(_ item: WatchHistoryItem, width: CGFloat) -> some View {
        NavigationLink(value: Route.movieDetail(movieId: item.movieId)) { HistoryPosterCard(item: item, width: width) }.buttonStyle(.plain)
    }
    private func refresh() async {
        error = await WatchHistorySync.sync(context: context)
        isLoading = false
    }
}

private struct HistoryCollectionPage: View {
    @Environment(\.dismiss) private var dismiss
    let collection: HistoryCollection
    let items: [WatchHistoryItem]
    let onResume: (WatchHistoryItem) -> Void
    let onMore: (WatchHistoryItem) -> Void
    let onRefresh: () async -> Void
    private var movies: [WatchHistoryItem] { LibraryHistory.movies(in: collection, from: items) }
    private var genres: [String] { LibraryHistory.genres(in: items) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        PhosphorView(.caretLeft, size: 18, color: Color.mirrorInk)
                            .frame(width: 44, height: 44)
                            .background(Color(mirrorHex: "18181B"), in: Circle())
                    }.accessibilityLabel("Back")
                    Text(collection.title).font(.mirrorH3).foregroundStyle(Color.mirrorInk)
                        .lineLimit(1).minimumScaleFactor(0.85).frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44, height: 44)
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(summary).font(.mirrorBodySmall).foregroundStyle(Color.mirrorTextSecondary)
                        if collection == .genres {
                            if genres.isEmpty { emptyState("No watched genres yet", message: "Finish a movie to see its genres here.") }
                            else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(genres, id: \.self) { name in
                                        let count = LibraryHistory.movies(in: .genre(name), from: items).count
                                        NavigationLink(value: HistoryCollection.genre(name)) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text(name).font(.mirrorBody)
                                                    Spacer(minLength: 4)
                                                    PhosphorView(.caretRight, size: 12, color: Color.mirrorTextTertiary)
                                                }
                                                Text("\(count) \(count == 1 ? "movie" : "movies")").font(.mirrorCaptionSmall).foregroundStyle(Color.mirrorTextTertiary)
                                            }.foregroundStyle(Color.mirrorInk).padding(16)
                                                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                                                .background(Color(mirrorHex: "121214"), in: RoundedRectangle(cornerRadius: 12))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        } else if movies.isEmpty {
                            emptyState(collection == .continuing ? "Nothing to continue" : "No watched movies yet",
                                message: collection == .continuing ? "Movies you start will appear here." : "Movies appear here after you finish more than 95%.")
                        } else if collection == .continuing {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(movies) { item in
                                    ContinueWatchingCard(title: item.title, subtitle: item.subtitle,
                                        imageURL: URL(string: item.backdropURL ?? item.posterURL ?? ""), timeRemaining: item.remainingTime,
                                        progress: item.progressPercentage, width: max(1, geometry.size.width - 32),
                                        onResume: { onResume(item) }, onMore: { onMore(item) })
                                }
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 20) {
                                ForEach(movies) { item in
                                    NavigationLink(value: Route.movieDetail(movieId: item.movieId)) {
                                        HistoryPosterCard(item: item, width: max(1, (geometry.size.width - 44) / 2), genreContext: selectedGenre)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 110)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.refreshable { await onRefresh() }
            }.background(Color(mirrorHex: "060606").ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Color.mirrorInk)
    }
    private var selectedGenre: String? {
        if case .genre(let name) = collection { return name }
        return nil
    }
    private var summary: String {
        if collection == .genres { return "Browse movies you’ve finished by genre." }
        let count = movies.count
        if collection == .continuing { return "\(count) \(count == 1 ? "movie" : "movies") in progress" }
        return "\(count) watched \(count == 1 ? "movie" : "movies")"
    }
    private func emptyState(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.mirrorH3).foregroundStyle(Color.mirrorInk)
            Text(message).font(.mirrorBodySmall).foregroundStyle(Color.mirrorTextTertiary)
        }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryPosterCard: View {
    let item: WatchHistoryItem
    var width: CGFloat = 125
    var genreContext: String? = nil
    private var subtitle: String {
        guard let genreContext else { return item.subtitle }
        return [item.year > 0 ? String(item.year) : nil, genreContext].compactMap { $0 }.joined(separator: " • ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyImage(url: URL(string: item.posterURL ?? "")) { state in
                if let image = state.image { image.resizable().scaledToFill() }
                else { Color(mirrorHex: "18181B") }
            }.frame(width: width, height: width * 1.5).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item.title).font(.system(size: width > 140 ? 14 : 13, weight: .medium)).foregroundStyle(Color.mirrorInk)
                .lineLimit(width > 140 ? 2 : 1).frame(maxWidth: .infinity, alignment: .leading)
            Text(subtitle).font(.mirrorCaptionSmall).foregroundStyle(Color.mirrorTextTertiary).lineLimit(1)
        }.frame(width: width, alignment: .leading)
    }
}
