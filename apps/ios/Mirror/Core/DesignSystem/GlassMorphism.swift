import SwiftUI

public struct GlassModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var opacity: Double
    public var borderOpacity: Double
    public var blurRadius: CGFloat

    public init(
        cornerRadius: CGFloat = Radius.xl,
        opacity: Double = 0.08,
        borderOpacity: Double = 0.12,
        blurRadius: CGFloat = 20
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.borderOpacity = borderOpacity
        self.blurRadius = blurRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.85)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.mirrorInk.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.mirrorInk.opacity(borderOpacity), lineWidth: 0.8)
            )
    }
}

public extension View {
    func glass(
        cornerRadius: CGFloat = Radius.xl,
        opacity: Double = 0.08,
        borderOpacity: Double = 0.12,
        blurRadius: CGFloat = 20
    ) -> some View {
        modifier(GlassModifier(
            cornerRadius: cornerRadius,
            opacity: opacity,
            borderOpacity: borderOpacity,
            blurRadius: blurRadius
        ))
    }
}
