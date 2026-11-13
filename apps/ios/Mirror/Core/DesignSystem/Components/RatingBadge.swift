import SwiftUI

public struct RatingBadge: View {
    public let rating: Double

    public init(rating: Double) {
        self.rating = rating
    }

    public var body: some View {
        HStack(spacing: 4) {
            PhosphorView(.starBold, size: 11)
                .foregroundColor(.mirrorAmber)

            Text(String(format: "%.1f", rating))
                .font(.mirrorCaption)
                .fontWeight(.bold)
                .foregroundColor(Color.mirrorInk)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .glass(cornerRadius: Radius.sm, opacity: 0.10, borderOpacity: 0.15)
    }
}
