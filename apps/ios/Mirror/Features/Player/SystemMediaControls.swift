import AVFoundation
import MediaPlayer

/// Owns only Mirror's command handlers and releases them when playback closes.
@MainActor final class SystemMediaControls {
  private var handlers: [(MPRemoteCommand, Any)] = []
  private var tick: Any?
  private weak var player: AVPlayer?
  private var observation: NSKeyValueObservation?
  private var title = ""

  func start(player: AVPlayer, title: String, play: @escaping @MainActor () -> Void,
             pause: @escaping @MainActor () -> Void, toggle: @escaping @MainActor () -> Void,
             seek: @escaping @MainActor (Double) -> Void) {
    stop()
    self.player = player
    self.title = title
    let center = MPRemoteCommandCenter.shared()
    register(center.playCommand, action: play)
    register(center.pauseCommand, action: pause)
    register(center.togglePlayPauseCommand, action: toggle)
    center.skipForwardCommand.preferredIntervals = [10]
    center.skipBackwardCommand.preferredIntervals = [10]
    register(center.skipForwardCommand) { [weak player] in seek((player?.currentTime().seconds ?? 0) + 10) }
    register(center.skipBackwardCommand) { [weak player] in seek((player?.currentTime().seconds ?? 0) - 10) }
    center.changePlaybackPositionCommand.isEnabled = true
    let target = center.changePlaybackPositionCommand.addTarget { event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let position = event.positionTime
      Task { @MainActor in seek(position) }
      return .success
    }
    handlers.append((center.changePlaybackPositionCommand, target))
    observation = player.observe(\.rate, options: [.initial, .new]) { [weak self] _, _ in
      Task { @MainActor in self?.refresh() }
    }
    tick = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    refresh()
  }

  private func register(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
    command.isEnabled = true
    let token = command.addTarget { _ in
      Task { @MainActor in action() }
      return .success
    }
    handlers.append((command, token))
  }

  func refresh() {
    guard let player else { return }
    let duration = player.currentItem?.duration.seconds ?? 0
    let position = player.currentTime().seconds
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: title,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
      MPMediaItemPropertyPlaybackDuration: duration.isFinite ? max(0, duration) : 0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position.isFinite ? max(0, position) : 0,
      MPNowPlayingInfoPropertyPlaybackRate: player.rate,
    ]
    #if os(macOS)
    MPNowPlayingInfoCenter.default().playbackState = player.rate == 0 ? .paused : .playing
    #endif
  }

  func stop() {
    guard player != nil || !handlers.isEmpty else { return }
    for (command, token) in handlers { command.removeTarget(token); command.isEnabled = false }
    handlers.removeAll()
    if let tick, let player { player.removeTimeObserver(tick) }
    tick = nil
    observation = nil
    player = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    #if os(macOS)
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    #endif
  }
}
