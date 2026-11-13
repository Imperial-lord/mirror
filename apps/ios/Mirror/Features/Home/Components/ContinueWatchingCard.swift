import SwiftUI
import NukeUI

public struct ContinueWatchingCard: View {
    public let title: String
    public let subtitle: String
    public let imageURL: URL?
    public let timeRemaining: String
    public let progress: Double
    public let width: CGFloat
    public var onResume: (() -> Void)?
    public var onMore: (() -> Void)?

    public init(
        title: String,
        subtitle: String = "",
        imageURL: URL?,
        timeRemaining: String = "",
        progress: Double = 0,
        width: CGFloat = 210,
        onResume: (() -> Void)? = nil,
        onMore: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.timeRemaining = timeRemaining
        self.progress = progress
        self.width = width
        self.onResume = onResume
        self.onMore = onMore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                HapticManager.shared.impact(.light)
                onResume?()
            } label: {
                // Landscape Artwork with Centered Play & Time Badge
                ZStack(alignment: .bottomTrailing) {
                    LazyImage(url: imageURL) { state in
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
                                    PhosphorView(.film, size: 22)
                                        .foregroundColor(Color.mirrorInk.opacity(0.3))
                                )
                        }
                    }
                    .frame(width: width, height: width * 122 / 210)
                    .clipped()

                    // Centered Play Circle
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                            )

                        PhosphorView(.playBold, size: 14, color: Color.white)
                            .offset(x: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    // Timestamp badge at bottom right
                    Text(timeRemaining)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.70))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        )
                        .padding(8)
                }
                .frame(width: width, height: width * 122 / 210)
                .overlay(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        Rectangle().fill(Color.mirrorInk)
                            .frame(width: geometry.size.width * min(1, max(0, progress)), height: 2)
                    }
                    .frame(height: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.6)
                )

            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue watching \(title)")

                // Bottom Title & Ellipsis
                HStack {
                    Button { onResume?() } label: {
                        Text(title)
                            .font(.system(size: width > 250 ? 15 : 13, weight: .medium))
                            .foregroundColor(Color.mirrorInk)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Menu { Button("Movie information") { onMore?() } } label: {
                        PhosphorView(.more, size: 16, color: Color.mirrorTextSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .tint(Color.mirrorInk)
                    .accessibilityLabel("More about \(title)")
                }
                .frame(width: width)

                // Subtitle
                Text(subtitle)
                    .font(.system(size: width > 250 ? 13 : 11, weight: .regular))
                    .foregroundColor(Color.mirrorInk.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
            .frame(width: width)
    }
}
