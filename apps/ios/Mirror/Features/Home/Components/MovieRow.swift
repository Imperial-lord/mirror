import SwiftUI

public struct MovieRow: View {
    public let title: String
    public let movies: [Movie]
    public var isLandscape: Bool = false
    public var isLoading: Bool = false
    public var onMovieTap: ((Movie) -> Void)?

    public init(
        title: String,
        movies: [Movie],
        isLandscape: Bool = false,
        isLoading: Bool = false,
        onMovieTap: ((Movie) -> Void)? = nil
    ) {
        self.title = title
        self.movies = movies
        self.isLandscape = isLandscape
        self.isLoading = isLoading
        self.onMovieTap = onMovieTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with subtle chevron
            NavigationLink(value: Route.seeAll(title: title, movies: movies)) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.mirrorInk)

                    Spacer()

                    PhosphorView(.caretRight, size: 12).foregroundStyle(Color.mirrorInk.opacity(0.35))
                }
                .padding(.horizontal, Spacing.md)
            }

            if isLoading && movies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(mirrorHex: "18181B"))
                                    .frame(width: isLandscape ? 210 : 125, height: isLandscape ? 122 : 185)
                                    .shimmer()

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(mirrorHex: "18181B"))
                                    .frame(width: 80, height: 10)
                                    .shimmer()
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(movies) { movie in
                            NavigationLink(value: Route.movieDetail(movieId: movie.id)) {
                                if isLandscape {
                                    LandscapeMovieCard(movie: movie)
                                } else {
                                    MoviePosterCard(movie: movie)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
    }
}
