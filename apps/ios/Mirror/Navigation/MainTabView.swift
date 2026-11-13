import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: AppTab = .home
    @State private var catalogViewModel = SearchViewModel()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(mirrorHex: "060606").ignoresSafeArea()

            // Tab View Stacks
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack {
                        HomeView()
                            .navigationDestination(for: Route.self) { route in
                                destinationView(for: route)
                            }
                    }
                case .catalog:
                    NavigationStack {
                        SearchView(viewModel: catalogViewModel)
                            .navigationDestination(for: Route.self) { route in
                                destinationView(for: route)
                            }
                    }
                case .library:
                    NavigationStack {
                        DownloadsView()
                            .navigationDestination(for: Route.self) { route in
                                destinationView(for: route)
                            }
                    }
                case .account:
                    NavigationStack {
                        ProfileView()
                            .navigationDestination(for: Route.self) { route in
                                destinationView(for: route)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Exact Behance Floating Pill Navigation Bar
            FloatingTabBarView(selectedTab: $selectedTab)
        }

    }

    @ViewBuilder
    private func destinationView(for route: Route) -> some View {
        switch route {
        case .seeAll(let title, let movies):
            SeeAllView(title: title, initialMovies: movies)
        case .movieDetail(let movieId):
            MovieDetailView(movieId: movieId)
        case .personDetail(let person):
            PersonDetailView(person: person)
        case .castAndCrew(let people):
            CastAndCrewView(people: people)
        case .watchlist:
            Text("Watchlist")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.mirrorInk)
        case .watchHistory:
            Text("Watch History")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.mirrorInk)
        case .settings:
            Text("Settings")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.mirrorInk)
        case .about:
            Text("About Mirror")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.mirrorInk)
        case .genreGrid(let genre):
            GenreDetailView(genre: genre)
        }
    }
}
