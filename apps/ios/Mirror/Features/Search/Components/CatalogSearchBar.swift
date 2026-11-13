import SwiftUI

public struct CatalogSearchBar: View {
    @Binding public var text: String
    public var onFilterTap: (() -> Void)?
    public var onClear: (() -> Void)?
    public var onBack: (() -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        onFilterTap: (() -> Void)? = nil,
        onClear: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self._text = text
        self.onFilterTap = onFilterTap
        self.onClear = onClear
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            // Main Search Capsule
            HStack(spacing: Spacing.xs) {
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                        isFocused = false
                        onBack?()
                    }) {
                        PhosphorView(.arrowLeft, size: 16, color: Color.mirrorInk.opacity(0.60))
                            .frame(width: 28, height: 28)
                    }
                } else {
                    PhosphorView(.searchLinear, size: 16, color: Color.mirrorTextTertiary)
                        .padding(.leading, 4)
                }

                TextField("Search", text: $text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.mirrorInk)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !text.isEmpty {
                    Button(action: {
                        text = ""
                        onClear?()
                    }) {
                        PhosphorView(.closeCircle, size: 16, color: Color.mirrorInk.opacity(0.40))
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(mirrorHex: "141417"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.6)
                    )
            )

            // Filter Drawer Button [ 🎛 ]
            Button(action: {
                HapticManager.shared.selection()
                onFilterTap?()
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(mirrorHex: "141417"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.6)
                        )

                    PhosphorView(.filter, size: 18, color: Color.mirrorInk)
                }
                .frame(width: 42, height: 42)
            }
            .accessibilityLabel("Filters")
            .buttonStyle(ScaleButtonStyle(scaleAmount: 0.94))
        }
    }
}
