import SwiftUI
import NukeUI

public struct RateReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRating: Int = 8
    @State private var reviewTitle: String = ""
    @State private var reviewBody: String = ""

    let movie: MovieDetail
    var onSubmit: (Int, String, String) -> Void

    public init(movie: MovieDetail, onSubmit: @escaping (Int, String, String) -> Void = { _, _, _ in }) {
        self.movie = movie
        self.onSubmit = onSubmit
    }

    public var body: some View {
        ZStack {
            Color(mirrorHex: "121215").ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                HStack {
                    Spacer()
                    Text("Rate the Movie")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.mirrorInk)
                    Spacer()
                    Button(action: { dismiss() }) {
                        PhosphorView(.close, size: 14)
                            .foregroundColor(Color.mirrorTextSecondary)
                            .padding(8)
                            .background(Color.mirrorInk.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.top, Spacing.md)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Movie Poster & Title
                        HStack(spacing: 14) {
                            if let poster = movie.posterURL {
                                LazyImage(url: poster) { state in
                                    if let image = state.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Color(mirrorHex: "18181B")
                                    }
                                }
                                .frame(width: 50, height: 75)
                                .cornerRadius(8)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color.mirrorInk)
                                    .lineLimit(2)

                                Text("\(String(movie.year)) • \(movie.genres?.first ?? "Movie")")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.mirrorTextTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(mirrorHex: "18181B"))
                        .cornerRadius(14)

                        // Rating Score Selector 1-10
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your Rating")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(1...10, id: \.self) { score in
                                        let isSelected = selectedRating == score
                                        Button(action: {
                                            HapticManager.shared.selection()
                                            selectedRating = score
                                        }) {
                                            Text("\(score)")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(isSelected ? Color.mirrorOnInk : Color.mirrorInk)
                                                .frame(width: 44, height: 44)
                                                .background(isSelected ? Color.mirrorInk : Color(mirrorHex: "18181B"))
                                                .clipShape(Circle())
                                                .overlay(
                                                    Circle()
                                                        .stroke(isSelected ? Color.mirrorInk : Color.mirrorInk.opacity(0.12), lineWidth: 1)
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }

                        // Review Title Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            TextField("Review headline (optional)", text: $reviewTitle)
                                .font(.system(size: 15))
                                .foregroundColor(Color.mirrorInk)
                                .padding(14)
                                .background(Color(mirrorHex: "18181B"))
                                .cornerRadius(12)
                        }

                        // Review Body Text Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Review")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            TextEditor(text: $reviewBody)
                                .font(.system(size: 15))
                                .foregroundColor(Color.mirrorInk)
                                .scrollContentBackground(.hidden)
                                .frame(height: 120)
                                .padding(10)
                                .background(Color(mirrorHex: "18181B"))
                                .cornerRadius(12)
                        }
                    }
                }

                // Solid White Pill CTA Button
                Button(action: {
                    HapticManager.shared.notification(.success)
                    onSubmit(selectedRating, reviewTitle, reviewBody)
                    dismiss()
                }) {
                    Text("Rate")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.mirrorOnInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.mirrorInk)
                        .clipShape(Capsule())
                }
                .padding(.bottom, Spacing.lg)
            }
            .padding(.horizontal, Spacing.md)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
