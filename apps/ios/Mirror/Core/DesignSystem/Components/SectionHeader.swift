import SwiftUI

public struct SectionHeader: View {
    public let title: String
    public var onSeeAll: (() -> Void)?

    public init(
        title: String,
        onSeeAll: (() -> Void)? = nil
    ) {
        self.title = title
        self.onSeeAll = onSeeAll
    }

    public var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            onSeeAll?()
        }) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.mirrorInk)

                Spacer()

                PhosphorView(.caretRight, size: 13)
                    .foregroundColor(Color.mirrorInk.opacity(0.35))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 4)
    }
}
