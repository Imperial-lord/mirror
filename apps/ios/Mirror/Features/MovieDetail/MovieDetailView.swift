import SwiftUI
import NukeUI

public struct MovieDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var viewModel: MovieDetailViewModel
    @State private var playbackRequestedAt = ContinuousClock.now

    public init(movieId: Int) {
        _viewModel = State(initialValue: MovieDetailViewModel(movieId: movieId))
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(mirrorHex: "060606").ignoresSafeArea()

            switch viewModel.state {
            case .idle, .loading:
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.mirrorInk)
                    Spacer()
                }
            case .error(let message):
                VStack(spacing: 12) {
                    Spacer()
                    PhosphorView(.warning, size: 40)
                        .foregroundColor(Color.mirrorInk.opacity(0.6))
                    Text("Failed to load details")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.mirrorInk)
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(Color.mirrorTextTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: {
                        Task { await viewModel.loadDetails() }
                    }) {
                        Text("Try Again")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.mirrorOnInk)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.mirrorInk)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
            case .loaded(let movie, let suggestions):
                Group {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            // 1. Hero Poster Section with Badges & Action Buttons
                            heroSection(movie: movie)

                            // 2. Trailers and Teasers Section
                            trailersSection(movie: movie)

                            // 4. Rating & Reviews Section
                            reviewsSection(movie: movie)
                                .id("reviews")

                            // 5. Cast & Crew Section
                            if viewModel.isLoadingCredits {
                                ProgressView()
                                    .tint(Color.mirrorInk)
                                    .frame(maxWidth: .infinity, minHeight: 100)
                                    .accessibilityLabel("Loading cast and crew")
                            } else if !viewModel.credits.isEmpty {
                                castSection(cast: viewModel.credits)
                                    .id("cast")
                            }

                            // 6. You May Also Like Section
                            if !suggestions.isEmpty {
                                suggestionsSection(suggestions: suggestions)
                                    .id("suggestions")
                            }

                            // Clearance for the floating Play button & tab bar
                            Spacer().frame(height: 150)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                }

                // Floating Bottom "▶ Play" CTA Button (Behance Board 12: sits above floating tab bar)
                floatingPlayCTA(movie: movie)
            }
        }
        .tint(Color.mirrorInk)
        .task { LibraryStore.shared.start() }
        .navigationBarHidden(true)
        .sheet(isPresented: $viewModel.isShowingDownloadSheet) {
            if case .loaded(let movie, _) = viewModel.state {
                DownloadSettingsSheet(movie: movie)
            }
        }
        .sheet(isPresented: $viewModel.isShowingAddToLibrarySheet) {
            if case .loaded(let movie, _) = viewModel.state {
                AddToLibrarySheet(movie: SavedMovie(movie: movie))
            }
        }
        .sheet(isPresented: $viewModel.isShowingRateSheet) {
            if case .loaded(let movie, _) = viewModel.state {
                RateReviewSheet(movie: movie) { rating, title, body in
                    // Handled rating
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.isShowingPlayer) {
            if case .loaded(let movie, _) = viewModel.state {
                MirrorVideoPlayerView(movie: movie, requestedAt: playbackRequestedAt)
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadDetails()
            }
        }
    }

    // MARK: - 1. Hero Section
    @ViewBuilder
    private func heroSection(movie: MovieDetail) -> some View {
        VStack(spacing: 16) {
            ZStack(alignment: .top) {
                // Background Poster / Backdrop
                ZStack(alignment: .bottom) {
                    if let poster = movie.posterURL ?? movie.backdropURL {
                        LazyImage(url: poster) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color(mirrorHex: "1C1C1C")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 420)
                        .clipped()
                    } else {
                        Color(mirrorHex: "1C1C1C")
                            .frame(maxWidth: .infinity)
                            .frame(height: 420)
                    }

                    // Dark Gradient Fade into Background
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(mirrorHex: "060606").opacity(0.3),
                            Color(mirrorHex: "060606").opacity(0.8),
                            Color(mirrorHex: "060606")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                }

                LinearGradient(colors: [Color(mirrorHex: "000000").opacity(scheme == .dark ? 0.55 : 0.86), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                    .allowsHitTesting(false)

                // Top Navigation Bar: Back Button & Rating Badges
                HStack {
                    Button(action: { dismiss() }) {
                        PhosphorView(.caretLeft, size: 18)
                            .foregroundStyle(Color.mirrorInk)
                            .frame(width: 40, height: 40)
                            .background(Color(mirrorHex: "121215").opacity(0.65))
                            .clipShape(Circle())
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        // IMDb Rating Pill (Translucent)
                        HStack(spacing: 3) {
                            Text("IMDb")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(Color.mirrorInk)
                            Text(String(format: "%.1f", movie.rating))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.mirrorInk)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(mirrorHex: "121215").opacity(0.75))
                        .overlay(Capsule().stroke(Color.mirrorInk.opacity(0.15), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 62)
            }

            // Movie Title & Metadata
            VStack(spacing: 8) {
                Text(movie.title)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color.mirrorInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)

                // Metadata Row: e.g. Horror • 2017 • 2h 1m
                HStack(spacing: 6) {
                    if let firstGenre = movie.genres?.first {
                        metadataPill(firstGenre)
                    }
                    metadataPill(String(movie.year))
                    metadataPill(movie.formattedRuntime)
                    if let lang = movie.language {
                        metadataPill(lang.uppercased())
                    }
                }
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.mirrorTextTertiary)
            }

            // Action Buttons: Download [⬇], Add to Library [+], Share [↗]
            HStack(spacing: 16) {
                // Download
                Button(action: {
                    HapticManager.shared.selection()
                    viewModel.isShowingDownloadSheet = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(mirrorHex: "1C1C1C"))
                            .frame(width: 44, height: 44)

                        PhosphorView(.downloadLinear, size: 20).foregroundStyle(Color.mirrorInk)
                    }
                }

                .accessibilityLabel("Download")

                // Add to Library
                Button(action: {
                    HapticManager.shared.selection()
                    viewModel.isShowingAddToLibrarySheet = true
                }) {
                    ZStack {
                        Circle()
                            .fill(LibraryStore.shared.favorites.contains(where: { $0.id == movie.id }) ? Color.mirrorInk : Color(mirrorHex: "1C1C1C"))
                            .frame(width: 44, height: 44)

                        PhosphorView(LibraryStore.shared.favorites.contains(where: { $0.id == movie.id }) ? .tickCircle : .add, size: 20, color: LibraryStore.shared.favorites.contains(where: { $0.id == movie.id }) ? Color.mirrorOnInk : Color.mirrorInk)
                    }
                }

                .accessibilityLabel("Add to Library")

                // Share
                ShareLink(item: movie.url) {
                    ZStack {
                        Circle()
                            .fill(Color(mirrorHex: "1C1C1C"))
                            .frame(width: 44, height: 44)

                        PhosphorView(.share, size: 20).foregroundStyle(Color.mirrorInk)
                    }
                }
                .accessibilityLabel("Share movie")
            }
            .padding(.top, 4)

            // Synopsis / Description Paragraph
            if let desc = movie.descriptionFull ?? movie.descriptionIntro, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(desc)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.mirrorTextSecondary)
                        .lineLimit(viewModel.isSynopsisExpanded ? nil : 3)
                        .lineSpacing(2)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isSynopsisExpanded.toggle()
                        }
                    }) {
                        Text(viewModel.isSynopsisExpanded ? "Read Less" : "Read More")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.mirrorInk)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 4)
            }
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.mirrorTextSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.mirrorInk.opacity(0.04), in: Capsule())
            .overlay(Capsule().stroke(Color.mirrorInk.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: - 2. Trailers and Teasers
    @ViewBuilder
    private func trailersSection(movie: MovieDetail) -> some View {
        if let code = movie.ytTrailerCode, !code.isEmpty,
           let url = URL(string: "https://www.youtube.com/watch?v=\(code)") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trailers and Teasers").font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, Spacing.md)
                Link(destination: url) {
                    trailerCard(title: "Official Trailer", imageURL: movie.screenshots.first ?? movie.backdropURL ?? movie.posterURL)
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    private func trailerCard(title: String, imageURL: URL?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let url = imageURL {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color(mirrorHex: "1C1C1C")
                        }
                    }
                } else {
                    Color(mirrorHex: "1C1C1C")
                }

                // Play overlay
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 44, height: 44)
                    PhosphorView(.playBold, size: 16)
                        .foregroundColor(Color.white)
                }

            }
            .frame(width: 300, height: 169)
            .cornerRadius(12)
            .clipped()

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white)
                .lineLimit(1)
        }
    }

    // MARK: - 4. Rating & Reviews Section
    @ViewBuilder
    private func reviewsSection(movie: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rating & Reviews")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.mirrorInk)
                .padding(.horizontal, Spacing.md)
            HStack {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", movie.rating))
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.mirrorInk)
                    Text("IMDb rating")
                        .font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary)
                }
                .frame(maxWidth: .infinity)
                Rectangle().fill(Color.mirrorInk.opacity(0.09)).frame(width: 1, height: 38)
                Button {
                    HapticManager.shared.selection()
                    viewModel.isShowingRateSheet = true
                } label: {
                    Text("Rate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.mirrorInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.mirrorInk.opacity(0.06), in: Capsule())
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(Color(mirrorHex: "121214"), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - 5. Cast & Crew
    @ViewBuilder
    private func castSection(cast: [Cast]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: Route.castAndCrew(people: cast)) {
                HStack {
                    Text("Cast & Crew")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    PhosphorView(.caretRight, size: 14, color: .mirrorInk)
                }
                .foregroundStyle(Color.mirrorInk)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                ForEach(Array(cast.prefix(6))) { person in
                    NavigationLink(value: Route.personDetail(person: person)) {
                        HStack(spacing: 10) {
                            LazyImage(url: person.avatarURL) { state in
                                if let image = state.image {
                                    image.resizable().scaledToFill()
                                        .frame(width: 44, height: 52)
                                } else {
                                    PhosphorView(.userFill, size: 22)
                                        .foregroundStyle(Color.mirrorInk.opacity(0.3))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color(mirrorHex: "222226"))
                                }
                            }
                            .frame(width: 44, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.mirrorInk)
                                    .lineLimit(2)
                                Text(person.characterName ?? person.creditRole)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.mirrorTextTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - 6. Suggestions
    @ViewBuilder
    private func suggestionsSection(suggestions: [Movie]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You May Also Like")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.mirrorInk)
                .padding(.horizontal, Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(suggestions) { movie in
                        NavigationLink(value: Route.movieDetail(movieId: movie.id)) {
                            MoviePosterCard(movie: movie)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    // MARK: - 7. Floating Play CTA
    @ViewBuilder
    private func floatingPlayCTA(movie: MovieDetail) -> some View {
        Button {
            HapticManager.shared.impact(.heavy)
            playbackRequestedAt = .now
            viewModel.isShowingPlayer = true
        } label: {
            HStack(spacing: 8) {
                PhosphorView(.playBold, size: 18, color: Color.mirrorOnInk)
                Text("Play").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color.mirrorOnInk)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.mirrorInk, in: Capsule())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, 76)
        .padding(.top, 16)
        .background {
            LinearGradient(colors: [.clear, Color(mirrorHex: "060606").opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }
}
