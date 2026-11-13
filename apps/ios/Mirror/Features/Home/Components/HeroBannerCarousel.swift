import SwiftUI

public struct HeroBannerCarousel: View {
    public let movies: [Movie]
    public var onWatchMovie: ((Movie) -> Void)?
    public var onAddToList: ((Movie) -> Void)?

    @State private var currentIndex: Int = 0
    @State private var timer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    public init(
        movies: [Movie],
        onWatchMovie: ((Movie) -> Void)? = nil,
        onAddToList: ((Movie) -> Void)? = nil
    ) {
        self.movies = movies
        self.onWatchMovie = onWatchMovie
        self.onAddToList = onAddToList
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // TabView Carousel
            TabView(selection: $currentIndex) {
                ForEach(Array(movies.prefix(5).enumerated()), id: \.element.id) { index, movie in
                    HeroBannerCard(
                        movie: movie,
                        onWatch: { onWatchMovie?(movie) },
                        onAddToList: { onAddToList?(movie) }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 420)
            .onReceive(timer) { _ in
                guard !movies.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    currentIndex = (currentIndex + 1) % min(movies.count, 5)
                }
            }

            // Custom Page Indicator Dots
            if movies.count > 1 {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<min(movies.count, 5), id: \.self) { index in
                        Capsule()
                            .fill(currentIndex == index ? Color.mirrorAccent : Color.mirrorBorder)
                            .frame(width: currentIndex == index ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentIndex)
                    }
                }
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(height: 420)
    }
}
