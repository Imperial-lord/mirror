import AppKit
import WebKit
import XCTest

@testable import MirrorDesktop

@MainActor final class TrailerPlayerTests: XCTestCase {
  private func trailer() throws -> MovieTrailer {
    try XCTUnwrap(MovieTrailer(code: "zSWdZVtXT7E", title: "A movie"))
  }
  private func until(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(8)
    while !condition() {
      if Date() > deadline {
        XCTFail("Trailer state did not update")
        throw URLError(.timedOut)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  func testOnlyValidYouTubeIdentifiersAreAccepted() {
    XCTAssertNotNil(MovieTrailer(code: "aB_01-xyZ98", title: "Movie"))
    for code in [
      nil, "", "short", "abcdefghijkl", "https://youtube.com/watch?v=123", "abcdefghi<>",
      "abcdefghij\n",
    ] {
      XCTAssertNil(MovieTrailer(code: code, title: "Movie"))
    }
  }
  func testEmbedIdentifiesAppAndKeepsYouTubeControlsWithoutInjectingMovieTitle() throws {
    let origin = try XCTUnwrap(TrailerDocument.origin(bundleID: "com.example.mirror"))
    let trailer = try XCTUnwrap(
      MovieTrailer(code: "zSWdZVtXT7E", title: "</script><script>bad()</script>"))
    let html = TrailerDocument.html(trailer, origin: origin, token: UUID())
    XCTAssertTrue(html.contains("youtube-nocookie.com/embed/zSWdZVtXT7E"))
    XCTAssertTrue(html.contains("origin=https://com.example.mirror"))
    XCTAssertTrue(html.contains("strict-origin-when-cross-origin"))
    XCTAssertTrue(html.contains("allowfullscreen"))
    XCTAssertTrue(html.contains("playsinline=1"))
    XCTAssertFalse(html.contains("controls=0"))
    XCTAssertFalse(html.contains("bad()"))
    XCTAssertNil(TrailerDocument.origin(bundleID: "https://attacker.example/path"))
    XCTAssertNil(TrailerDocument.origin(bundleID: "bad\"host"))
  }
  func testRealWebViewMessageBridgeBecomesReadyAndCloseRemovesIt() async throws {
    let player = TrailerPlayerController(document: { _, _, token in
      "<html><body><script>window.webkit.messageHandlers.trailer.postMessage({event:'ready',token:'\(token.uuidString)'});</script></body></html>"
    })
    defer { player.stop() }
    player.load(try trailer())
    try await until { player.state == .ready }
    XCTAssertFalse(player.webView.configuration.websiteDataStore.isPersistent)
    player.stop()
    XCTAssertNil(player.token)
    let present =
      try await player.webView.evaluateJavaScript(
        "Boolean(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.trailer)"
      ) as? Bool
    XCTAssertEqual(present, false)
  }
  func testRetryAndDismissDiscardOldOrSubframeCallbacks() throws {
    let player = TrailerPlayerController(document: { _, _, _ in "<html></html>" })
    defer { player.stop() }
    player.load(try trailer())
    let old = try XCTUnwrap(player.token)
    player.load(try trailer())
    let current = try XCTUnwrap(player.token)
    player.receive(["event": "error", "code": 101, "token": old.uuidString], mainFrame: true)
    player.receive(["event": "error", "code": 101, "token": current.uuidString], mainFrame: false)
    XCTAssertEqual(player.state, .loading)
    player.receive(["event": "ready", "token": current.uuidString], mainFrame: true)
    XCTAssertEqual(player.state, .ready)
    player.stop()
    player.receive(["event": "error", "code": 101, "token": current.uuidString], mainFrame: true)
    XCTAssertEqual(player.state, .ready)
  }
  func testRestrictedOrMissingTrailerShowsAnInAppFailure() throws {
    for code in [100, 101, 150, 153, 5] {
      let player = TrailerPlayerController(document: { _, _, _ in "<html></html>" })
      player.load(try trailer())
      let token = try XCTUnwrap(player.token)
      player.receive(["event": "error", "code": code, "token": token.uuidString], mainFrame: true)
      guard case .failed = player.state else { return XCTFail("Expected trailer failure") }
      XCTAssertNil(player.token)
      player.stop()
    }
  }
  func testTimeoutEndsLoadingAndReadyCancelsTimeout() async throws {
    let player = TrailerPlayerController(
      timeout: .milliseconds(50), document: { _, _, _ in "<html></html>" })
    defer { player.stop() }
    player.load(try trailer())
    try await until {
      if case .failed = player.state { return true }
      return false
    }
    player.load(try trailer())
    let token = try XCTUnwrap(player.token)
    player.receive(["event": "ready", "token": token.uuidString], mainFrame: true)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(player.state, .ready)
  }
  /// Explicit opt-in only; ordinary CI uses local HTML fixtures and never depends on YouTube.
  func testLiveTrailerPlaybackWhenEnabled() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["MIRROR_LIVE_TRAILER_TEST"] == "1")
    let player = TrailerPlayerController()
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 960, height: 540),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = player.webView
    window.makeKeyAndOrderFront(nil)
    defer { player.stop(); window.close() }
    player.load(try trailer())
    let deadline = Date().addingTimeInterval(40)
    var started = false
    while Date() < deadline {
      if case .failed(let message) = player.state { XCTFail(message); return }
      if player.state == .ready {
        if !started {
          _ = try await player.webView.evaluateJavaScript("player.playVideo(); null;")
          started = true
        }
        if let state = try await player.webView.evaluateJavaScript("player.getPlayerState()") as? Int, state == 1 { return }
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("The live trailer never entered the playing state")
  }
}
