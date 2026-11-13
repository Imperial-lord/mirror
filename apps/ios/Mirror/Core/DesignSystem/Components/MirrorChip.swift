import SwiftUI

public struct MirrorChip: View {
    public let title: String
    public let isSelected: Bool
    public let action: () -> Void

    public init(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            Text(title)
                .font(.mirrorButtonSmall)
                .foregroundColor(isSelected ? Color.mirrorInk : .mirrorTextSecondary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Color.mirrorAccent)
                        } else {
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Color.mirrorInk.opacity(0.06))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(
                            isSelected ? Color.clear : Color.mirrorInk.opacity(0.08),
                            lineWidth: 0.8
                        )
                )
        }
        .buttonStyle(ScaleButtonStyle(scaleAmount: 0.95))
    }
}
