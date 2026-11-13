import SwiftUI
import NukeUI

public struct RecommendationSetupView: View {
    public var onComplete: () -> Void

    @State private var movies: [Movie] = []
    @State private var selectedMovieIds: Set<Int> = []
    @State private var isLoading = true

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (Behance Board 07)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select your favorite movies")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.mirrorInk)
                        .lineLimit(2)

                    Text("Choose at least 1 favourite")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.mirrorTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.md)

                // 3-Column Poster Grid
                if isLoading && movies.isEmpty {
                    Spacer()
                    ProgressView()
                        .tint(Color.mirrorInk)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(movies) { movie in
                                let isSelected = selectedMovieIds.contains(movie.id)

                                Button(action: {
                                    HapticManager.shared.selection()
                                    if isSelected {
                                        selectedMovieIds.remove(movie.id)
                                    } else {
                                        selectedMovieIds.insert(movie.id)
                                    }
                                }) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack(alignment: .topTrailing) {
                                            LazyImage(url: movie.posterURL) { state in
                                                if let image = state.image {
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                } else {
                                                    Color(mirrorHex: "18181B")
                                                }
                                            }
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(2/3, contentMode: .fit)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(isSelected ? Color.mirrorInk : Color.clear, lineWidth: 2)
                                            )

                                            if isSelected {
                                                Circle()
                                                    .fill(Color.mirrorInk)
                                                    .frame(width: 22, height: 22)
                                                    .overlay(
                                                        PhosphorView(.check, size: 11)
                                                            .foregroundColor(Color.mirrorOnInk)
                                                    )
                                                    .padding(6)
                                            }
                                        }

                                        Text(movie.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Color.mirrorInk)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, 120)
                    }
                }

                Spacer(minLength: 0)
            }

            // Bottom Action Bar (Behance Board 07: Skip + Continue)
            VStack {
                Spacer()

                HStack(spacing: 12) {
                    // Skip Button
                    Button(action: {
                        HapticManager.shared.selection()
                        onComplete()
                    }) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.mirrorInk)
                            .frame(width: 100, height: 52)
                            .background(Color(mirrorHex: "171719"))
                            .clipShape(Capsule())
                    }

                    // Continue Button
                    Button(action: {
                        HapticManager.shared.impact(.medium)
                        // Save to Firestore if needed
                        Task {
                            for id in selectedMovieIds {
                                if let movie = movies.first(where: { $0.id == id }) {
                                    await FirestoreService.shared.toggleFavorite(movie: movie, isFavorite: true)
                                }
                            }
                        }
                        onComplete()
                    }) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedMovieIds.isEmpty ? Color.mirrorOnInk.opacity(0.4) : Color.mirrorOnInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(selectedMovieIds.isEmpty ? Color.mirrorInk.opacity(0.4) : Color.mirrorInk)
                            .clipShape(Capsule())
                    }
                    .disabled(selectedMovieIds.isEmpty)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.lg)
                .background(
                    LinearGradient(
                        colors: [Color(mirrorHex: "060606").opacity(0), Color(mirrorHex: "060606").opacity(0.95), Color(mirrorHex: "060606")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .allowsHitTesting(false),
                    alignment: .bottom
                )
            }
        }
        .task {
            await loadRecommendationMovies()
        }
    }

    private func loadRecommendationMovies() async {
        do {
            let fetched = try await MovieRepository.shared.fetchMovies(endpoint: APIEndpoint.listMovies(limit: 15, page: 1, quality: nil, minimumRating: nil, queryTerm: nil, genre: nil, sortBy: "download_count", orderBy: "desc"))
            await MainActor.run {
                self.movies = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
