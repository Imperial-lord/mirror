import SwiftUI
import NukeUI

public struct GenreCard: View {
    public let genre: String
    public let imageURL: URL?
    public var width: CGFloat?
    public var onTap: (() -> Void)?

    public init(
        genre: String,
        imageURL: URL? = nil,
        width: CGFloat? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.genre = genre
        self.imageURL = imageURL
        self.width = width
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            onTap?()
        }) {
            HStack(spacing: 8) {
                Text(genre)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.mirrorInk)
                    .lineLimit(1)
                    .padding(.leading, 14)

                Spacer()

                // Character Circle Cutout
                ZStack {
                    Circle()
                        .fill(Color(mirrorHex: "222226"))
                        .frame(width: 46, height: 46)

                    if let imageURL {
                        LazyImage(url: imageURL) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                PhosphorView(.film, size: 14)
                                    .foregroundColor(Color.mirrorInk.opacity(0.35))
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    } else {
                        PhosphorView(.popcorn, size: 16)
                            .foregroundColor(Color.mirrorInk.opacity(0.35))
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Color.mirrorInk.opacity(0.12), lineWidth: 0.8)
                )
                .padding(.trailing, 8)
            }
            .frame(width: width)
            .frame(height: 78)
            .background(Color(mirrorHex: "151518"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.6)
            )
        }
        .buttonStyle(ScaleButtonStyle(scaleAmount: 0.96))
    }
}
