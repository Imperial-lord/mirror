import SwiftUI
import NukeUI

public struct SearchView: View {
    @State private var viewModel: SearchViewModel

    private let availableFilters = ["All", "Drama", "Thriller", "Horror", "Action", "Sci-Fi", "Comedy", "Crime"]

    public init(viewModel: SearchViewModel = SearchViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 16) {
                // Centered Top Header "Catalog" matching Behance Board 13
                Text("Catalog")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color.mirrorInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xs)

                // Search Input with Filter Drawer Button
                CatalogSearchBar(
                    text: $viewModel.query,
                    onFilterTap: {
                        viewModel.isFilterSheetPresented = true
                    },
                    onClear: {
                        viewModel.clear()
                    },
                    onBack: {
                        viewModel.clear()
                    }
                )
                .padding(.horizontal, Spacing.md)

                // Horizontal Filters Section (Behance Board 13)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filters")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.mirrorTextTertiary)
                        .padding(.horizontal, Spacing.md)

                    ScrollViewReader { filterProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(activeProductionFilters, id: \.0) { key, title in
                                Button {
                                    switch key {
                                    case "country": viewModel.selectedCountry = nil
                                    case "studio": viewModel.selectedStudio = nil
                                    default: viewModel.selectedYear = nil
                                    }
                                    Task { await viewModel.performSearch() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(title)
                                        PhosphorView(.close, size: 9)
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.mirrorInk)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Color(mirrorHex: "222226"), in: Capsule())
                                    .overlay(Capsule().stroke(Color.mirrorInk.opacity(0.24), lineWidth: 1))
                                }
                                .accessibilityLabel("Remove \(title) filter")
                            }
                            ForEach(availableFilters, id: \.self) { filter in
                                let isSelected = (viewModel.selectedGenre ?? "All") == filter
                                Button(action: {
                                    HapticManager.shared.selection()
                                    viewModel.selectedGenre = (filter == "All" || viewModel.selectedGenre == filter) ? nil : filter
                                    Task { await viewModel.performSearch() }
                                }) {
                                    HStack(spacing: 6) {
                                        Text(filter)
                                        if isSelected && filter != "All" {
                                            PhosphorView(.close, size: 9)
                                        }
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(isSelected ? Color.mirrorInk : Color.mirrorTextSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Color(mirrorHex: "222226") : Color(mirrorHex: "121215"))
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.mirrorInk.opacity(0.24) : Color.mirrorInk.opacity(0.08), lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                                }
                                .id(filter)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                    .onChange(of: viewModel.selectedGenre) { _, genre in
                        withAnimation { filterProxy.scrollTo(genre ?? "All", anchor: .leading) }
                    }
                    }
                }

                // 2-Column Grid (Behance Board 13)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        if viewModel.isEmpty {
                            noResultsView.padding(.top, 24)
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.searchResults) { movie in
                                NavigationLink(value: Route.movieDetail(movieId: movie.id)) {
                                    CatalogGridCard(movie: movie)
                                }
                                .buttonStyle(.plain)
                                .task {
                                    if movie.id == viewModel.searchResults.last?.id && !viewModel.usesManualPagination {
                                        await viewModel.loadNextPage()
                                    }
                                }
                            }
                        }
                        if viewModel.usesManualPagination && viewModel.canLoadMore && !viewModel.isSearching && viewModel.errorMessage == nil {
                            VStack(spacing: 12) {
                                if viewModel.searchResults.isEmpty {
                                    Text("Looking for matching movies").font(.mirrorBodySmall).foregroundStyle(Color.mirrorTextSecondary)
                                }
                                Button(viewModel.searchResults.isEmpty ? "Search more movies" : "Load more") { Task { await viewModel.loadNextPage() } }
                                    .font(.mirrorButton).foregroundStyle(Color.mirrorInk)
                            }.padding(.vertical, 24)
                        }
                        if viewModel.isSearching {
                            ProgressView().tint(Color.mirrorInk).padding(24)
                        }
                        if let error = viewModel.errorMessage {
                            VStack(spacing: 12) {
                                Text(error).font(.system(size: 14)).foregroundStyle(Color.mirrorTextSecondary)
                                Button("Try again") {
                                    Task {
                                        if viewModel.searchResults.isEmpty { await viewModel.performSearch() }
                                        else { await viewModel.loadNextPage() }
                                    }
                                }
                                .foregroundStyle(Color.mirrorInk)
                            }.padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 100)

                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await APIClient.shared.invalidateResponses()
                    await viewModel.performSearch()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Color.mirrorInk)
        .fullScreenCover(isPresented: $viewModel.isFilterSheetPresented) {
            FiltersSheetView(
                selectedGenre: $viewModel.selectedGenre,
                minimumRating: $viewModel.minimumRating,
                sortBy: $viewModel.sortBy,
                selectedCountry: $viewModel.selectedCountry,
                selectedStudio: $viewModel.selectedStudio,
                selectedYear: $viewModel.selectedYear,
                onApply: {
                    Task { await viewModel.performSearch() }
                }
            )
        }
        .task {
            if !viewModel.hasSearched {
                await viewModel.loadIdleCatalog()
            }
        }
    }

    private var activeProductionFilters: [(String, String)] {
        var filters: [(String, String)] = []
        if let country = CatalogFilterOption.countries.first(where: { $0.id == viewModel.selectedCountry }) { filters.append(("country", country.name)) }
        if let studio = CatalogFilterOption.studios.first(where: { $0.id == viewModel.selectedStudio }) { filters.append(("studio", studio.name)) }
        if let year = viewModel.selectedYear { filters.append(("year", String(year))) }
        return filters
    }

    // MARK: - Behance Catalog Grid Card
    private struct CatalogGridCard: View {
        let movie: Movie

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Color(mirrorHex: "18181B")
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(mirrorHex: "18181B"))

                    if let url = movie.posterURL {
                        LazyImage(url: url) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color(mirrorHex: "18181B")
                            }
                        }
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.mirrorInk.opacity(0.08), lineWidth: 1)
                )

                // Title
                Text(movie.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.mirrorInk)
                    .lineLimit(1)

                // Metadata: Year • Genre
                HStack(spacing: 4) {
                    Text(String(movie.year))
                    if let firstGenre = movie.genres?.first {
                        Text("•")
                        Text(firstGenre)
                    }
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color.mirrorTextTertiary)
                .lineLimit(1)
            }
        }
    }

    // MARK: - No Results View
    private var noResultsView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(mirrorHex: "121215"))
                    .frame(width: 80, height: 80)

                PhosphorView(.searchLinear, size: 32)
                    .foregroundColor(Color.mirrorTextTertiary)
            }
            .padding(.top, 40)

            Text("We couldn't find anything")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.mirrorInk)

            Text("Check for typos or try searching for something else.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.mirrorTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
