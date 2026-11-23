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
    XCTAssertTrue(controller.diagnosticsReport.contains("retry_scheduled source=stream"))
    XCTAssertTrue(controller.diagnosticsReport.contains("recovery_failed source=stream"))
    XCTAssertFalse(controller.diagnosticsReport.contains("Fixture"))
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

  func testDiagnosticsKeepsValidatedReferencesAndBoundsTheReport() throws {
    let legacy = try JSONDecoder().decode(PlaybackSession.self, from: Data("""
    {"id":"fixture-session","path":"/fixture"}
    """.utf8))
    XCTAssertNil(legacy.diagnosticID)
    let playbackID = try XCTUnwrap(UUID(uuidString: "f16fb802-6128-41a7-b725-e0fbeddac112"))
    let requestID = "abcdef0123456789abcdef0123456789"
    let session = try JSONDecoder().decode(PlaybackSession.self, from: Data("""
    {"id":"fixture-session","path":"/fixture","diagnostic_id":"\(playbackID.uuidString)"}
    """.utf8))
    XCTAssertEqual(session.diagnosticID.flatMap(UUID.init(uuidString:)), playbackID)

    let diagnostics = PlaybackDiagnostics()
    diagnostics.begin(offline: true)
    XCTAssertTrue(diagnostics.report.contains("opening source=offline"))
    diagnostics.begin(offline: false)
    diagnostics.associate(PlaybackDiagnosticReference(requestID: "https://private.example", status: 503))
    diagnostics.record(.openFailed, reason: .busy)
    XCTAssertFalse(diagnostics.report.contains("private.example"))
    XCTAssertTrue(diagnostics.report.contains("reason=busy http_status=503"))

    diagnostics.begin(offline: false)
    diagnostics.associate(PlaybackDiagnosticReference(requestID: requestID, playbackID: playbackID, status: 201))
    for _ in 0..<30 { diagnostics.record(.firstFrame, since: .now) }
    let report = diagnostics.report
    XCTAssertEqual(report.split(separator: "\n").count, 26)
    XCTAssertTrue(report.contains("request_id=\(requestID)"))
    XCTAssertTrue(report.contains("playback_id=\(playbackID.uuidString.lowercased())"))
    XCTAssertFalse(report.contains("503"))
  }
}
