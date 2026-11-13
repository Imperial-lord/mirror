import SwiftUI
import NukeUI

public struct GenreDetailView: View {
    public let genre: Genre
    @Environment(\.dismiss) private var dismiss

    @State private var movies: [Movie] = []
    @State private var featuredMovie: Movie? = nil
    @State private var selectedCategory: ContentCategory = .all
    @State private var isLoading = true

    private let repository = MovieRepository()
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    public init(genre: Genre) {
        self.genre = genre
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color(mirrorHex: "060606").ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    // Featured Backdrop Hero
                    ZStack(alignment: .bottomLeading) {
                        if let featured = featuredMovie {
                            LazyImage(url: featured.backdropURL ?? featured.posterURL) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Rectangle().fill(Color(mirrorHex: "18181B"))
                                }
                            }
                            .frame(height: 220)
                            .clipped()
                        } else {
                            Rectangle()
                                .fill(Color(mirrorHex: "18181B"))
                                .frame(height: 220)
                        }

                        // Gradient Overlay
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color(mirrorHex: "060606").opacity(0.4), location: 0.5),
                                .init(color: Color(mirrorHex: "060606"), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        Text(genre.rawValue)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Color.mirrorInk)
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, 12)
                    }
                    .frame(height: 220)

                    // Category Pill Switcher
                    CategoryPillBar(selectedCategory: $selectedCategory)
                        .padding(.horizontal, Spacing.md)

                    // 2-Column Movie Grid
                    if isLoading && movies.isEmpty {
                        LazyVGrid(columns: columns, spacing: Spacing.md) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(mirrorHex: "18181B"))
                                    .frame(height: 220)
                                    .shimmer()
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    } else {
                        LazyVGrid(columns: columns, spacing: Spacing.md) {
                            ForEach(movies) { movie in
                                NavigationLink(value: Route.movieDetail(movieId: movie.id)) {
                                    MoviePosterCard(movie: movie, width: 165)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.bottom, 110)
            }

            // Top Bar with Back Button
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    PhosphorView(.caretLeft, size: 16)
                        .foregroundColor(Color.mirrorInk)
                        .frame(width: 38, height: 38)
                        .background(Color(mirrorHex: "000000").opacity(0.40))
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)
        }
        .navigationBarHidden(true)
        .task {
            await loadGenreMovies()
        }
    }

    private func loadGenreMovies() async {
        isLoading = true
        do {
            let fetched = try await repository.fetchMovies(endpoint: .listMovies(
                limit: 20,
                genre: genre.rawValue,
                sortBy: "rating"
            ))
            self.movies = fetched
            self.featuredMovie = fetched.first
        } catch {}
        isLoading = false
    }
}
