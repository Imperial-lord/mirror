import SwiftUI

public struct MetadataPill: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.mirrorCaption)
            .foregroundColor(.mirrorTextSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(Color.mirrorSurface3.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.5)
            )
    }
}
