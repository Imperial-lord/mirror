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
}
