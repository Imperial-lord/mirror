import SwiftUI

public struct GenresListView: View {
    @Environment(\.dismiss) private var dismiss

    private let genres = [
        "Action", "Comedy", "Adventure", "Animation",
        "Crime", "Drama", "Fantasy", "Horror",
        "Music", "Romance", "Sci-Fi", "Thriller"
    ]

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    public init() {}

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        PhosphorView(.caretLeft, size: 16)
                            .foregroundColor(Color.mirrorInk)
                            .frame(width: 40, height: 40)
                    }

                    Spacer()

                    Text("Genres")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.mirrorInk)

                    Spacer()

                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: Spacing.sm) {
                        ForEach(genres, id: \.self) { genre in
                            NavigationLink(value: Route.genreGrid(genre: Genre(rawValue: genre) ?? .action)) {
                                GenreCard(genre: genre)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationBarHidden(true)
    }
}
