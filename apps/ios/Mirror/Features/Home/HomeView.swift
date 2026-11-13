import SwiftUI
import SwiftData
import FirebaseFirestore

public struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var resumeMovie: ResumeMovie?
    @State private var selectedMovie: Int?
    @State private var historyError: String?
    @State private var isLoadingHistory = true
    private var ownedHistory: [WatchHistoryItem] { watchHistory.filter { $0.userId == AuthService.shared.currentUser?.uid } }
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var watchHistory: [WatchHistoryItem]

    public init() {}

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            Group {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 24) {
                        // 1. Exact Behance Hero Poster Section
                        if viewModel.isLoading && viewModel.heroMovies.isEmpty {
                            Rectangle().fill(Color.mirrorSurface1)
                                .frame(height: 470).shimmer()
                        } else if !viewModel.heroMovies.isEmpty {
                            HomeHeroSection(movies: viewModel.heroMovies) { movie in
                                selectedMovie = movie.id
                            }
                        }

                        if let error = viewModel.errorMessage {
                            VStack(spacing: 12) {
                                Text(error).font(.subheadline).foregroundStyle(.secondary)
                                Button("Try again") { Task { await viewModel.loadAll() } }
                            }.padding(16)
                        }
                        // 2. Continue Watching (Behance placement)
                        continueWatchingSection
                        if let historyError { Text(historyError).font(.mirrorBodySmall).foregroundStyle(Color.mirrorTextSecondary).padding(.horizontal, 16) }
                        if let error = viewModel.recommendationError {
                            Text(error).font(.mirrorBodySmall).foregroundStyle(Color.mirrorTextSecondary)
                            Button("Try again") { Task { await personalize() } }.tint(Color.mirrorInk)
                        }

                    // 4. Selected For You (Vertical Cards)
                    MovieRow(
                        title: "Selected For You",
                        movies: viewModel.selectedForYou,
                        isLoading: viewModel.isLoading || viewModel.isPersonalizing || isLoadingHistory
                    )

                    // 5. Popular Now (Landscape Cards)
                    MovieRow(
                        title: "Popular Now",
                        movies: viewModel.trendingMovies,
                        isLandscape: true,
                        isLoading: viewModel.isLoading
                    )

                    // 6. Top rated on Mirror (Vertical Cards)
                    MovieRow(
                        title: "Top rated on Mirror",
                        movies: viewModel.topRated,
                        isLoading: viewModel.isLoading
                    )

                    ForEach([Genre.thriller] + Genre.catalogGenres.filter { $0 != .thriller }) { genre in
                        VStack(spacing: 10) {
                            MovieRow(title: genre.bestTitle, movies: viewModel.genreMovies[genre] ?? [], isLandscape: true,
                                isLoading: viewModel.genreMovies[genre] == nil && viewModel.genreErrors[genre] == nil)
                            if let error = viewModel.genreErrors[genre] {
                                Text(error).font(.mirrorBodySmall).foregroundStyle(Color.mirrorTextSecondary)
                                Button("Try again") { Task { await viewModel.loadGenre(genre, retry: true) } }.tint(Color.mirrorInk)
                            }
                        }.task(id: viewModel.collectionRevision) { await viewModel.loadGenre(genre) }
                    }

                }
                .padding(.bottom, 110) // Clearance for floating bottom pill bar
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                await APIClient.shared.invalidateResponses()
                await viewModel.loadAll()
                await syncContinueWatching()
                await personalize()
            }
            }
        }
        .tint(Color.mirrorInk)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedMovie) { MovieDetailView(movieId: $0) }
        .fullScreenCover(item: $resumeMovie, onDismiss: { Task { await syncContinueWatching(); await personalize() } }) { item in
            ResumeMoviePlayer(movieId: item.id, position: item.position, requestedAt: item.requestedAt)
        }
        .task {
            async let progress: Void = syncContinueWatching()
            if viewModel.heroMovies.isEmpty {
                await viewModel.loadAll()
            }
            await progress
            await personalize()
        }
    }

    // MARK: - Continue Watching
    @ViewBuilder
    private var continueWatchingSection: some View {
        let inProgress = ownedHistory.filter(\.isInProgress)
        if !inProgress.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Continue Watching").font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, Spacing.md)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(inProgress) { item in
                            ContinueWatchingCard(title: item.title, subtitle: item.subtitle, imageURL: URL(string: item.backdropURL ?? item.posterURL ?? ""),
                                timeRemaining: item.remainingTime, progress: item.progressPercentage, onResume: { resumeMovie = ResumeMovie(id: item.movieId, position: item.progressSeconds) },
                                onMore: { selectedMovie = item.movieId })
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
    }

    @MainActor
    private func syncContinueWatching() async {
        historyError = await WatchHistorySync.sync(context: modelContext)
        isLoadingHistory = false
    }
    @MainActor
    private func personalize() async {
        let all = (try? modelContext.fetch(FetchDescriptor<WatchHistoryItem>())) ?? []
        let owned = all.filter { $0.userId == AuthService.shared.currentUser?.uid }
        await viewModel.personalize(history: owned.map(WatchPreference.init))
    }
}

struct ResumeMovie: Identifiable {
    let id: Int
    let position: Double
    let requestedAt = ContinuousClock.now
}

struct ResumeMoviePlayer: View {
    @Environment(\.dismiss) private var dismiss
    let movieId: Int
    let position: Double
    let requestedAt: ContinuousClock.Instant
    @State private var movie: MovieDetail?
    @State private var failed = false
    var body: some View {
        ZStack {
            Color(mirrorHex: "000000").ignoresSafeArea()
            if let movie {
                MirrorVideoPlayerView(movie: movie, resumePosition: position, requestedAt: requestedAt)
            } else {
                VStack(spacing: 18) {
                    if failed {
                        Text("Unable to open this movie").foregroundStyle(Color.mirrorInk)
                        Button("Try again") { Task { await load() } }.tint(Color.mirrorInk)
                    } else { ProgressView().tint(Color.mirrorInk) }
                    Button("Back") { dismiss() }.tint(Color.mirrorInk)
                }
            }
        }
        .task { await load() }
    }
    private func load() async {
        failed = false
        do { movie = try await MovieRepository.shared.fetchMovieDetail(id: movieId) }
        catch { if !Task.isCancelled { failed = true } }
    }
}
