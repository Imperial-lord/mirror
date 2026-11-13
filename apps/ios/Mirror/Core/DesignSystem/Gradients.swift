import SwiftUI

public enum MirrorGradient {
    public static let heroFade = LinearGradient(
        colors: [.clear, .mirrorBlack],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let heroTopFade = LinearGradient(
        colors: [Color.mirrorBlack.opacity(0.6), .clear],
        startPoint: .top,
        endPoint: .center
    )

    public static let detailFade = LinearGradient(
        stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: 0.4),
            .init(color: .mirrorBlack, location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let cardOverlay = LinearGradient(
        colors: [.clear, Color.black.opacity(0.7)],
        startPoint: .center,
        endPoint: .bottom
    )

    public static let accentGlow = LinearGradient(
        colors: [.mirrorAccent, .mirrorAccentDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
