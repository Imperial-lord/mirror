import SwiftUI
import NukeUI

public struct HomeHeroSection: View {
    @Environment(\.colorScheme) private var scheme
    public let movies: [Movie]
    public var onMovieTap: ((Movie) -> Void)?
    @State private var currentIndex = 0
    private let timer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    public init(movies: [Movie], onMovieTap: ((Movie) -> Void)? = nil) {
        self.movies = movies
        self.onMovieTap = onMovieTap
    }

    public var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(movies.prefix(5).enumerated()), id: \.element.id) { index, movie in
                Button { onMovieTap?(movie) } label: {
                    ZStack(alignment: .bottomLeading) {
                        LazyImage(url: movie.largePosterURL ?? movie.posterURL) { state in
                            if let image = state.image { image.resizable().scaledToFill() }
                            else { Color.mirrorSurface1 }
                        }
                        .frame(maxWidth: .infinity).frame(height: 470).clipped()
                        LinearGradient(colors: [Color(mirrorHex: "000000").opacity(scheme == .dark ? 0.4 : 0.8), .clear, .clear, .mirrorBackground], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(movie.title).font(.system(size: 24, weight: .medium)).lineLimit(2)
                            HStack(spacing: 10) {
                                if let genre = movie.genres?.first { Text(genre) }
                                if let rating = movie.mpaRating, !rating.isEmpty { Text(rating) }
                                Text(String(movie.year))
                            }
                            .font(.system(size: 12)).foregroundStyle(Color.mirrorTextSecondary)
                            HStack(spacing: 6) {
                                ForEach(0..<min(movies.count, 5), id: \.self) { page in
                                    Capsule().fill(page == currentIndex ? Color.mirrorInk : Color.mirrorInk.opacity(0.25))
                                        .frame(width: page == currentIndex ? 18 : 4, height: 3)
                                }
                            }.padding(.top, 8)
                        }
                        .padding(16).padding(.bottom, 12)
                    }
                    .foregroundStyle(Color.mirrorInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(movie.title)")
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 470)
        .onReceive(timer) { _ in
            guard !movies.isEmpty else { return }
            withAnimation { currentIndex = (currentIndex + 1) % min(movies.count, 5) }
        }
        .onChange(of: movies.map(\.id)) { _, _ in currentIndex = 0 }
    }
}
