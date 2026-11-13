import SwiftUI

@Observable
public final class MovieDetailViewModel {
    public enum State {
        case idle
        case loading
        case loaded(movie: MovieDetail, suggestions: [Movie])
        case error(String)
    }

    public var state: State = .idle
    public var isShowingDownloadSheet: Bool = false
    public var isShowingAddToLibrarySheet: Bool = false
    public var isShowingRateSheet: Bool = false
    public var isShowingPlayer: Bool = false
    public var isSynopsisExpanded: Bool = false
    public var credits: [Cast] = []
    public var isLoadingCredits = false

    private let repository: MovieRepositoryProtocol
    private let movieId: Int

    public init(movieId: Int, repository: MovieRepositoryProtocol = MovieRepository()) {
        self.movieId = movieId
        self.repository = repository
    }

    @MainActor
    public func loadDetails() async {
        state = .loading
        credits = []
        isLoadingCredits = true
        defer { isLoadingCredits = false }
        do {
            async let detailTask = repository.fetchMovieDetail(id: movieId)
            async let suggestionsTask = repository.fetchSuggestions(movieId: movieId)

            let detail = try await detailTask
            let suggestions = (try? await suggestionsTask) ?? []

            self.state = .loaded(movie: detail, suggestions: suggestions)
            if let people = try? await PeopleMetadataService.shared.credits(movieIMDb: detail.imdbCode), !Task.isCancelled {
                credits = people
            }
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

}
