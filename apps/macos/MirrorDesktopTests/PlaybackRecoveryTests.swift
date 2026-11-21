import XCTest
@testable import MirrorDesktop

@MainActor final class PlaybackRecoveryTests: XCTestCase {
  final class DisconnectedSource: OfflineDownloadSource {
    var attempts = 0
    func open(hash: String) async throws -> URL { attempts += 1; throw URLError(.notConnectedToInternet) }
    func close() {}
    func subtitles(imdb: String, language: String) async throws -> SubtitleTrack { throw URLError(.notConnectedToInternet) }
  }
  func testNetworkFailureStopsAfterTwoRetriesAndManualRetryPreservesPausedPosition() async throws {
    let source = DisconnectedSource()
    let movie = try JSONDecoder().decode(MovieDetail.self, from: Data("""
    {"id":1,"url":"","imdb_code":"tt1234567","title":"Fixture","year":2020,"rating":7,"runtime":100,
    "torrents":[{"url":"","hash":"fixture","quality":"1080p","type":"web","seeds":1,"peers":1,"size":"1 GB","size_bytes":1000,"date_uploaded":""}]}
    """.utf8))
    let controller = DesktopPlayerController(source: source, resumeProvider: { _ in nil })
    controller.start(DesktopPlayback(movie: movie))
    controller.wantsPlay = false
    controller.position = 123
    defer { controller.stop() }
    for _ in 0..<70 {
      if controller.failure != nil { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual(source.attempts, 3)
    XCTAssertNotNil(controller.failure)
    XCTAssertFalse(controller.showsLoadingIndicator)
    XCTAssertEqual(controller.position, 123)
    XCTAssertFalse(controller.wantsPlay)
    controller.retryPlayback()
    for _ in 0..<10 {
      if source.attempts > 3 { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual(source.attempts, 4)
    XCTAssertNil(controller.failure)
    XCTAssertFalse(controller.wantsPlay)
    XCTAssertEqual(controller.position, 123)
    controller.stop()
    try await Task.sleep(for: .seconds(3))
    XCTAssertEqual(source.attempts, 4, "Closing playback cancels queued reconnects")
  }
}
