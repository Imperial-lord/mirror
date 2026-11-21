import AppKit
import XCTest

@testable import MirrorDesktop

final class DesktopPlaybackTests: XCTestCase {
  @MainActor
  func testBackRestoresTheOriginatingSectionAndPopsOneScreenAtATime() {
    for section in [DesktopSection.home, .catalog, .library] {
      let session = DesktopSession()
      session.navigate(section)
      session.open(1)
      let moviePath = session.path
      session.path.append(DesktopRoute.collection("Filmography", [2, 3]))
      let collectionPath = session.path
      session.open(2)
      session.goBack()
      XCTAssertEqual(session.path, collectionPath)
      session.goBack()
      XCTAssertEqual(session.path, moviePath)
      session.goBack()
      XCTAssertTrue(session.path.isEmpty)
      XCTAssertEqual(session.section, section)
      session.goBack()
      XCTAssertTrue(session.path.isEmpty, "Back at the root must be safe")
    }
  }
  @MainActor
  func testLoadingRemainsVisibleUntilTheFirstVideoFrame() {
    let controller = DesktopPlayerController()
    XCTAssertTrue(controller.showsLoadingIndicator)
    controller.loading = false
    controller.ready = true
    XCTAssertTrue(controller.showsLoadingIndicator, "A ready item can still have no visible frame")
    controller.hasReadyFrame = true
    XCTAssertFalse(controller.showsLoadingIndicator)
    controller.failure = "Unavailable"
    controller.hasReadyFrame = false
    XCTAssertFalse(controller.showsLoadingIndicator, "Show the error, not a perpetual spinner")
  }

  @MainActor
  func testSeekingAndBufferingShowLoadingButAnOrdinaryPauseDoesNot() {
    let controller = DesktopPlayerController()
    controller.loading = false
    controller.hasReadyFrame = true
    controller.seeking = true
    XCTAssertTrue(controller.showsLoadingIndicator)
    controller.seeking = false
    controller.buffering = true
    XCTAssertTrue(controller.showsLoadingIndicator)
    controller.buffering = false
    controller.wantsPlay = false
    XCTAssertFalse(controller.showsLoadingIndicator)
  }

  @MainActor
  func testAudioOutputChangePausesWithoutDiscardingPosition() {
    let controller = DesktopPlayerController()
    controller.position = 125
    controller.wantsPlay = true
    controller.pauseForAudioChange()
    XCTAssertFalse(controller.wantsPlay)
    XCTAssertEqual(controller.position, 125)
    XCTAssertEqual(controller.player.rate, 0)
    controller.stop()
  }

  @MainActor
  func testSleepPreservesIntentAndPositionAndClosedPlaybackDoesNotRestart() {
    let controller = DesktopPlayerController()
    controller.position = 240
    controller.wantsPlay = false
    controller.suspendForSleep()
    XCTAssertFalse(controller.wantsPlay)
    XCTAssertEqual(controller.position, 240)
    controller.stop()
    controller.resumeAfterSleep()
    XCTAssertNil(controller.player.currentItem)
    XCTAssertFalse(controller.wantsPlay)
  }

  @MainActor
  func testMuteRestoresTheChosenVolume() {
    let controller = DesktopPlayerController()
    controller.setVolume(0.35)
    controller.toggleMute()
    XCTAssertEqual(controller.volume, 0)
    XCTAssertEqual(controller.player.volume, 0)
    controller.toggleMute()
    XCTAssertEqual(controller.volume, 0.35)
    XCTAssertEqual(controller.player.volume, 0.35)
    controller.setVolume(0)
    controller.toggleMute()
    XCTAssertEqual(controller.volume, 0.35)
  }
  @MainActor
  func testVolumeIconFollowsSliderAndMuteChanges() {
    let controller = DesktopPlayerController()
    let cases: [(Float, PhosphorIcon)] = [
      (0, .speakerNone), (0.01, .speakerLow), (0.5, .speakerLow),
      (0.51, .speakerHigh), (1, .speakerHigh)
    ]
    for (volume, icon) in cases {
      controller.setVolume(volume)
      XCTAssertEqual(controller.volumeIcon, icon)
      XCTAssertNotNil(NSImage(named: NSImage.Name(icon.assetName)), "Speaker asset must render in the Mac bundle")
    }
    controller.toggleMute()
    XCTAssertEqual(controller.volumeIcon, .speakerNone)
    controller.toggleMute()
    XCTAssertEqual(controller.volumeIcon, .speakerHigh)
  }
  func testSubtitleParsingIgnoresMarkupAndPreservesTiming() {
    let cues = SubtitleParser.parse(
      "1\n00:00:01,500 --> 00:00:03,000\n<i>A story &amp; a world.</i>\n\n2\n00:00:05,000 --> 00:00:04,000\nInvalid"
    )
    XCTAssertEqual(cues, [SubtitleCue(start: 1.5, end: 3, text: "A story & a world.")])
  }
  func testOfflineRangesRejectTruncatedResponses() {
    XCTAssertTrue(
      DownloadRange.valid(header: "bytes 0-99/200", offset: 0, end: 99, total: 200, size: 100))
    XCTAssertFalse(
      DownloadRange.valid(header: "bytes 0-99/200", offset: 0, end: 99, total: 200, size: 40))
  }
  func testFavoritesAndFoldersStayConsistent() {
    var selection = LibrarySelection(favorite: false)
    selection.togglePlaylist("travel")
    XCTAssertTrue(selection.favorite)
    selection.toggleFavorite()
    XCTAssertFalse(selection.favorite)
    XCTAssertTrue(selection.playlists.isEmpty)
  }
  func testTorrentDecodesWithoutTypeFieldInSuggestionsPayload() throws {
    let suggestionJSON = """
    {
      "status": "ok",
      "status_message": "Query was successful",
      "data": {
        "movie_count": 4,
        "movies": [
          {
            "id": 6792,
            "url": "https://yts.mx/movies/spider-man-homecoming-2017",
            "imdb_code": "tt2250912",
            "title": "Spider-Man: Homecoming",
            "year": 2017,
            "rating": 7.4,
            "runtime": 133,
            "genres": ["Action", "Adventure", "Sci-Fi"],
            "torrents": [
              {
                "url": "https://yts.mx/torrent/download/123",
                "hash": "CDED33F7FBF3E4E073778848FAD17674C0A35B82",
                "quality": "720p",
                "seeds": 23,
                "peers": 21,
                "size": "809.06 MB",
                "size_bytes": 848360899,
                "date_uploaded": "2015-10-31 22:22:51"
              }
            ]
          }
        ]
      }
    }
    """
    let data = Data(suggestionJSON.utf8)
    let response = try JSONDecoder().decode(YTSResponse<MovieSuggestionsData>.self, from: data)
    let movies = try XCTUnwrap(response.data.movies)
    XCTAssertEqual(movies.count, 1)
    let firstMovie = try XCTUnwrap(movies.first)
    XCTAssertEqual(firstMovie.title, "Spider-Man: Homecoming")
    let torrent = try XCTUnwrap(firstMovie.torrents?.first)
    XCTAssertNil(torrent.type)
    XCTAssertEqual(torrent.quality, "720p")
  }
  @MainActor
  func testMovieDetailViewModelExposesLoadedSuggestions() async throws {
    let movieDetailJSON = """
    {
      "id": 13596,
      "url": "https://yts.mx/movies/spider-man-far-from-home-2019",
      "imdb_code": "tt6320628",
      "title": "Spider-Man: Far from Home",
      "year": 2019,
      "rating": 7.4,
      "runtime": 129
    }
    """
    let movieDetail = try JSONDecoder().decode(MovieDetail.self, from: Data(movieDetailJSON.utf8))
    let suggestedMovieJSON = """
    {
      "id": 6792,
      "url": "https://yts.mx/movies/spider-man-homecoming-2017",
      "imdb_code": "tt2250912",
      "title": "Spider-Man: Homecoming",
      "year": 2017,
      "rating": 7.4,
      "runtime": 133
    }
    """
    let suggestedMovie = try JSONDecoder().decode(Movie.self, from: Data(suggestedMovieJSON.utf8))

    struct MockSuggestionRepository: MovieRepositoryProtocol {
      let detail: MovieDetail
      let suggestions: [Movie]
      func fetchMovies(endpoint: APIEndpoint) async throws -> [Movie] { [] }
      func fetchMovieDetail(id: Int) async throws -> MovieDetail { detail }
      func fetchSuggestions(movieId: Int) async throws -> [Movie] { suggestions }
    }

    let repo = MockSuggestionRepository(detail: movieDetail, suggestions: [suggestedMovie])
    let model = MovieDetailViewModel(movieId: 13596, repository: repo)
    await model.loadDetails()

    if case .loaded(let movie, let suggestions) = model.state {
      XCTAssertEqual(movie.id, 13596)
      XCTAssertEqual(suggestions.count, 1)
      XCTAssertEqual(suggestions.first?.title, "Spider-Man: Homecoming")
    } else {
      XCTFail("ViewModel state should be .loaded with suggestions")
    }
  }
}
