import SwiftUI

public struct MirrorSecondaryButton: View {
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
                    PhosphorView(icon, size: 14)
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(Color.mirrorInk)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(height: 50)
            .background(Color.mirrorInk.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(ScaleButtonStyle(scaleAmount: 0.96))
    }
}
