import XCTest

@testable import MirrorDesktop

final class DesktopPlaybackTests: XCTestCase {
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
}
