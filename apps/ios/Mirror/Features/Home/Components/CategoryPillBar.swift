import SwiftUI

public enum ContentCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case movies = "Movies"

    public var id: String { rawValue }
}

public struct CategoryPillBar: View {
    @Binding public var selectedCategory: ContentCategory

    public init(selectedCategory: Binding<ContentCategory>) {
        self._selectedCategory = selectedCategory
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(ContentCategory.allCases) { category in
                Button(action: {
                    HapticManager.shared.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedCategory = category
                    }
                }) {
                    Text(category.rawValue)
                        .font(.system(size: 13, weight: selectedCategory == category ? .medium : .regular))
                        .foregroundColor(selectedCategory == category ? Color.mirrorInk : Color.mirrorInk.opacity(0.50))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(
                            Group {
                                if selectedCategory == category {
                                    Capsule()
                                        .fill(Color.mirrorInk.opacity(0.16))
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                .buttonStyle(ScaleButtonStyle(scaleAmount: 0.95))
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color(mirrorHex: "141417"))
                .overlay(
                    Capsule()
                        .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
