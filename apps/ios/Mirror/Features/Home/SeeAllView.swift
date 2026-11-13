import SwiftUI

public struct SeeAllView: View {
    public let title: String
    public let initialMovies: [Movie]
    public var onMovieTap: ((Movie) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var movies: [Movie] = []

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    public init(
        title: String,
        initialMovies: [Movie],
        onMovieTap: ((Movie) -> Void)? = nil
    ) {
        self.title = title
        self.initialMovies = initialMovies
        self.onMovieTap = onMovieTap
    }

    public var body: some View {
        ZStack {
            Color.mirrorBlack.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(movies.isEmpty ? initialMovies : movies) { movie in
                        NavigationLink(value: Route.movieDetail(movieId: movie.id)) {
                            MoviePosterCard(movie: movie, width: 110)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.mirrorBlack.opacity(0.8), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            if movies.isEmpty {
                movies = initialMovies
            }
        }
    }
}
