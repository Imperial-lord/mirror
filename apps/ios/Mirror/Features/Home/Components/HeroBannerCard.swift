import SwiftUI
import NukeUI

public struct HeroBannerCard: View {
    public let movie: Movie
    public var onWatch: (() -> Void)?
    public var onAddToList: (() -> Void)?

    public init(
        movie: Movie,
        onWatch: (() -> Void)? = nil,
        onAddToList: (() -> Void)? = nil
    ) {
        self.movie = movie
        self.onWatch = onWatch
        self.onAddToList = onAddToList
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop Image with NukeUI
            GeometryReader { geo in
                let minX = geo.frame(in: .global).minX
                let parallaxOffset = -minX / 3.5

                LazyImage(url: movie.backdropURL ?? movie.posterURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 420)
                            .offset(x: parallaxOffset)
                            .clipped()
                    } else if state.isLoading {
                        Rectangle()
                            .fill(Color.mirrorSurface2)
                            .shimmer()
                    } else {
                        Rectangle()
                            .fill(Color.mirrorSurface2)
                    }
                }
            }
            .frame(height: 420)

            // Top gradient to protect status bar & top navigation icons
            MirrorGradient.heroTopFade
                .frame(height: 160)
                .frame(maxHeight: .infinity, alignment: .top)

            // Bottom gradient to blend seamlessly into mirrorBlack canvas
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.mirrorBlack.opacity(0.4), location: 0.4),
                    .init(color: Color.mirrorBlack.opacity(0.85), location: 0.75),
                    .init(color: Color.mirrorBlack, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)

            // Content overlay
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Genre & Year Pills
                HStack(spacing: Spacing.xs) {
                    if let genres = movie.genres?.prefix(2) {
                        ForEach(Array(genres), id: \.self) { genre in
                            MetadataPill(genre)
                        }
                    }
                    MetadataPill(String(movie.year))
                }

                // Display Title
                Text(movie.title)
                    .font(.mirrorDisplay)
                    .fontWeight(.bold)
                    .foregroundColor(.mirrorTextPrimary)
                    .lineLimit(2)
                    .shadow(color: Color.mirrorOnInk.opacity(0.6), radius: 8, x: 0, y: 2)
                    .padding(.top, 2)

                // Rating & Runtime Row
                HStack(spacing: Spacing.xs) {
                    if movie.rating > 0 {
                        RatingBadge(rating: movie.rating)
                    }

                    if movie.runtime > 0 {
                        Text("•")
                            .foregroundColor(.mirrorTextTertiary)
                        Text(movie.formattedRuntime)
                            .font(.mirrorCaption)
                            .foregroundColor(.mirrorTextSecondary)
                    }
                }
                .padding(.vertical, 4)

                // Action Buttons Row
                HStack(spacing: Spacing.sm) {
                    NavigationLink(value: Route.movieDetail(movieId: movie.id)) {
                        HStack(spacing: Spacing.xs) {
                            PhosphorView(.playBold, size: 16, color: Color.mirrorInk)
                            Text("Watch")
                                .font(.mirrorButton)
                        }
                        .foregroundColor(Color.mirrorInk)
                        .padding(.horizontal, Spacing.xl)
                        .frame(height: 52)
                        .background(MirrorGradient.accentGlow)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                        .shadowGlow()
                    }
                    .buttonStyle(ScaleButtonStyle())

                    MirrorSecondaryButton(title: "My List", icon: .add) {
                        onAddToList?()
                    }
                }
                .padding(.top, Spacing.xs)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xxl) // Leave space for page dots
        }
        .frame(height: 420)
        .clipped()
    }
}
