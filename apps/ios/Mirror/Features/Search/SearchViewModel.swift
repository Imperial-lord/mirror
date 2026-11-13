import SwiftUI

@Observable
public final class SearchViewModel {
    public var query = "" {
        didSet {
            requestID = UUID()
            canLoadMore = false
            debouncer.call { [weak self] in
                Task { await self?.performSearch() }
            }
        }
    }
    public var recentSearches: [Movie] = []
    public var topSearches: [Movie] = []
    public var searchResults: [Movie] = []
    public var matchingPersons: [Cast] = []
    public var selectedGenre: String?
    public var selectedCountry: String?
    public var selectedStudio: String?
    public var selectedYear: Int?
    public var minimumRating = 0
    public var sortBy = "like_count"
    public var isSearching = false
    public var hasSearched = false
    public var isFilterSheetPresented = false
    public var errorMessage: String?
    public var canLoadMore = false
    private var page = 1
    private var partialTitle: PartialTitle?
    private var requestID = UUID()
    private let pageSize = 30
    private let repository: MovieRepositoryProtocol
    private let metadata: any CatalogMetadataProviding
    private let debouncer = Debouncer(delay: 0.35)

    public var hasExtendedFilters: Bool { selectedCountry != nil || selectedStudio != nil || selectedYear != nil }
    var usesManualPagination: Bool { hasExtendedFilters || partialTitle != nil }

    public var isEmpty: Bool {
        hasSearched && searchResults.isEmpty && !isSearching && errorMessage == nil && !canLoadMore
    }

    public init(repository: MovieRepositoryProtocol = MovieRepository()) {
        self.repository = repository
        self.metadata = CatalogMetadataService.shared
    }

    init(repository: MovieRepositoryProtocol, metadata: any CatalogMetadataProviding) {
        self.repository = repository
        self.metadata = metadata
    }

    @MainActor
    public func loadIdleCatalog() async { await performSearch() }

    private struct Selection: Equatable {
        let query: String
        let genre: String?
        let rating: Int
        let sort: String
        let country: String?
        let studio: String?
        let year: Int?
        var needsLocalFiltering: Bool { country != nil || studio != nil || year != nil }
    }

    private struct PartialTitle {
        let anchor: String
        private let words: [String]

        init?(_ query: String) {
            let words = Self.tokens(query)
            guard words.count > 1,
                  let anchor = words.dropLast().max(by: { $0.count < $1.count }), anchor.count >= 3 else { return nil }
            self.anchor = anchor
            self.words = words
        }

        func matches(_ movie: Movie) -> Bool {
            [movie.title, movie.titleEnglish, movie.titleLong].compactMap { $0 }.contains { title in
                var remaining = words[...]
                for word in Self.tokens(title) {
                    if let prefix = remaining.first, word.hasPrefix(prefix) { remaining.removeFirst() }
                }
                return remaining.isEmpty
            }
        }

        private static func tokens(_ text: String) -> [String] {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
    }

    private var selection: Selection {
        Selection(query: query.trimmingCharacters(in: .whitespacesAndNewlines), genre: selectedGenre,
                  rating: minimumRating, sort: sortBy, country: selectedCountry, studio: selectedStudio, year: selectedYear)
    }

    @MainActor
    public func performSearch() async {
        requestID = UUID()
        page = 0
        partialTitle = nil
        canLoadMore = false
        hasSearched = true
        searchResults = []
        await loadBatch(reset: true)
    }

    @MainActor
    public func loadNextPage() async {
        guard canLoadMore, !isSearching else { return }
        await loadBatch(reset: false)
    }

    // Keep the upstream cursor, not the number of filtered rows. An empty batch
    // must not imply the entire catalog has no matches or end pagination early.
    @MainActor
    private func loadBatch(reset: Bool) async {
        let id = requestID
        let filters = selection
        isSearching = true
        errorMessage = nil
        do {
            var cursor = page
            var more = true
            var matches: [Movie] = []
            var partial = partialTitle
            for _ in 0..<6 {
                try Task.checkCancellation()
                func endpoint(query: String) -> APIEndpoint {
                    .listMovies(limit: pageSize, page: cursor + 1, minimumRating: filters.rating > 0 ? filters.rating : nil,
                                queryTerm: query.isEmpty ? nil : query, genre: filters.genre, sortBy: filters.sort)
                }
                let movies: [Movie]
                let sourceHasMore: Bool
                if let year = filters.year {
                    let result = try await repository.fetchYearMovies(endpoint: endpoint(query: filters.query), year: year)
                    movies = result.movies
                    sourceHasMore = result.hasMore
                } else {
                    var candidates = try await repository.fetchMovies(endpoint: endpoint(query: partial?.anchor ?? filters.query))
                    guard requestID == id, selection == filters else { return }
                    // The API can return zero for a partial phrase even when its complete title exists.
                    if cursor == 0, candidates.isEmpty, let fallback = PartialTitle(filters.query) {
                        candidates = try await repository.fetchMovies(endpoint: endpoint(query: fallback.anchor))
                        partial = fallback
                    }
                    sourceHasMore = candidates.count == pageSize
                    movies = partial.map { candidates.filter($0.matches) } ?? candidates
                }
                guard requestID == id, selection == filters else { return }
                let dated = movies.filter { filters.year == nil || $0.year == filters.year }
                if filters.country != nil || filters.studio != nil {
                    let production = try await metadata.production(for: dated)
                    matches += dated.filter { movie in
                        guard let info = production[movie.imdbCode] else { return false }
                        return (filters.country.map { info.countries.contains($0) } ?? true)
                            && (filters.studio.map { info.studios.contains($0) } ?? true)
                    }
                } else { matches += dated }
                cursor += 1
                more = sourceHasMore
                if !more || !matches.isEmpty || (!filters.needsLocalFiltering && partial == nil) { break }
            }
            guard requestID == id, selection == filters else { return }
            searchResults = unique((reset ? [] : searchResults) + matches)
            page = cursor
            partialTitle = partial
            canLoadMore = more
        } catch {
            guard requestID == id, selection == filters else { return }
            // On failure keep the cursor unchanged, so Retry cannot skip movies.
            errorMessage = reset ? "Couldn’t load movies. Please try again." : "Couldn’t load more movies. Please try again."
        }
        guard requestID == id, selection == filters else { return }
        isSearching = false
    }

    public func clear() {
        requestID = UUID()
        query = ""
        partialTitle = nil
        searchResults = []
        matchingPersons = []
        errorMessage = nil
        isSearching = false
        hasSearched = false
        canLoadMore = false
    }

    private func unique(_ movies: [Movie]) -> [Movie] {
        var seen: Set<Int> = []
        return movies.filter { seen.insert($0.id).inserted }
    }
}
