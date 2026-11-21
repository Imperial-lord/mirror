import AVFoundation
import MediaPlayer
import XCTest
@testable import MirrorDesktop

@MainActor final class SystemMediaControlsTests: XCTestCase {
  func testPublishesMovieAndClearsCommandsOnClose() {
    let controls = SystemMediaControls()
    let player = AVPlayer()
    controls.start(player: player, title: "Test movie", play: {}, pause: {}, toggle: {}, seek: { _ in })
    XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Test movie")
    XCTAssertTrue(MPRemoteCommandCenter.shared().playCommand.isEnabled)
    controls.stop()
    XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    XCTAssertFalse(MPRemoteCommandCenter.shared().playCommand.isEnabled)
    controls.stop()
  }
  func testReplacingSessionPublishesNewTitle() {
    let controls = SystemMediaControls()
    let player = AVPlayer()
    for title in ["First", "Second"] {
      controls.start(player: player, title: title, play: {}, pause: {}, toggle: {}, seek: { _ in })
    }
    XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Second")
    controls.stop()
  }
}
