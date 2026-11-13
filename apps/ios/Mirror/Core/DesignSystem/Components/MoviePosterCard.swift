import SwiftUI
import NukeUI

public struct MoviePosterCard: View {
    public let movie: Movie
    public var width: CGFloat
    public var onTap: (() -> Void)?

    public init(
        movie: Movie,
        width: CGFloat = 125,
        onTap: (() -> Void)? = nil
    ) {
        self.movie = movie
        self.width = width
        self.onTap = onTap
    }

    private var imageHeight: CGFloat {
        width * 1.48 // Aspect ratio matching Behance
    }

    public var body: some View {
        if let onTap {
            Button { HapticManager.shared.selection(); onTap() } label: { cardContent }
                .buttonStyle(ScaleButtonStyle(scaleAmount: 0.96))
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Poster Image
                LazyImage(url: movie.posterURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if state.isLoading {
                        Rectangle()
                            .fill(Color(mirrorHex: "18181B"))
                            .shimmer()
                    } else {
                        Rectangle()
                            .fill(Color(mirrorHex: "18181B"))
                            .overlay(
                                PhosphorView(.film, size: 20)
                                    .foregroundColor(Color.mirrorInk.opacity(0.3))
                            )
                    }
                }
                .frame(width: width, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.6)
                )

                // Title
                Text(movie.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.mirrorInk)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)

                // Subtitle: Year • Genre
                HStack(spacing: 4) {
                    Text(String(movie.year))
                    if let firstGenre = movie.genres?.first {
                        Text("•")
                        Text(firstGenre)
                    }
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color.mirrorInk.opacity(0.55))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width)
    }
}
