import SwiftUI

public struct MirrorLogoView: View {
    public var size: CGFloat = 28
    public var color: Color = Color.mirrorInk

    public init(size: CGFloat = 28, color: Color = Color.mirrorInk) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        VStack(spacing: size * 0.12) {
            // Top Circle
            Circle()
                .fill(color)
                .frame(width: size * 0.48, height: size * 0.48)

            // Bottom Inverted Semicircle / Mirror reflection
            SemiCircleShape()
                .fill(color)
                .frame(width: size * 0.54, height: size * 0.27)
        }
        .frame(width: size, height: size)
    }
}

private struct SemiCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
