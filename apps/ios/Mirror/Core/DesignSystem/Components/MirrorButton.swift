import SwiftUI

public struct MirrorButton: View {
    public let title: String
    public let icon: PhosphorIcon?
    public var isFullWidth: Bool
    public let action: () -> Void

    public init(
        title: String,
        icon: PhosphorIcon? = nil,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isFullWidth = isFullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    PhosphorView(icon, size: 15)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(Color.mirrorOnInk)
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(height: 50)
            .background(Color.mirrorInk)
            .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle(scaleAmount: 0.96))
    }
}
