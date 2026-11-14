import AVFoundation
import AppKit
import IOKit.pwr_mgt
import SwiftUI

@MainActor @Observable final class DesktopPlayerController {
  let player = AVPlayer()
  var loading = true
  var buffering = false
  var playing = false
  var wantsPlay = true
  var position: Double = 0
  var duration: Double = 0
  var volume: Float = 1
  private var volumeBeforeMute: Float = 1
  var rate: Float = 1
  var quality = "1080p"
  var subtitle = "off"
  var actualSubtitle = "off"
  var caption = ""
  var subtitleError: String?
  var failure: String?
  var ready = false
  private var request: DesktopPlayback?
  private let source: any OfflineDownloadSource
  private let resumeProvider: @MainActor (Int) async -> (position: Double, updatedAt: Date)?
  init(
    source: (any OfflineDownloadSource)? = nil,
    resumeProvider: @escaping @MainActor (Int) async -> (position: Double, updatedAt: Date)? = {
      id in
      guard AuthService.shared.isAuthenticated else { return nil }
      return try? await FirestoreService.shared.playbackCheckpoint(movieId: id)
    }
  ) {
    self.source = source ?? PlaybackService()
    self.resumeProvider = resumeProvider
  }
  private var prepareTask: Task<Void, Never>?
  private var subtitleTask: Task<Void, Never>?
  private var observations: [NSKeyValueObservation] = []
  private var itemObservation: NSKeyValueObservation?
  private var tick: Any?
  private var cues: [SubtitleCue] = []
  private var generation = UUID()
  private var seekTarget: Double = 0
  private var lastSave = Date.distantPast
  private var sleepAssertion: IOPMAssertionID = 0
  var checkpoint: ((Double, Double) -> Void)?
  var choices: [Torrent] { MovieQuality.choices(request?.movie.torrents ?? []) }
  var subtitleChoices: [String] {
    guard let saved = request?.offline else { return SubtitleLanguage.codes }
    return SubtitleLanguage.codes.filter { saved.subtitles[$0] != nil }
  }
  var offline: Bool { request?.offline != nil }
  var qualityLabel: String { request?.offline?.quality ?? MovieQuality.label(quality) }
  func start(_ request: DesktopPlayback) {
    self.request = request
    wantsPlay = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true
    quality =
      choices.first(where: { $0.quality == "1080p" })?.quality ?? choices.first?.quality ?? "1080p"
    duration = Double(request.movie.runtime) * 60
    if let file = request.offline?.file { DownloadStore.shared.retainPlaybackFile(file) }
    observations = [
      player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
        Task { @MainActor in
          guard let self else { return }
          self.playing = self.player.timeControlStatus == .playing
          self.buffering =
            self.wantsPlay && self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
          self.updateSleep()
        }
      }
    ]
    tick = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.updateTime() }
    }
    prepareTask = Task {
      let cloud = await resumeProvider(request.movie.id)
      var resume = cloud?.position ?? 0
      if let local = request.offline,
        (local.lastPlayedAt ?? .distantPast) > (cloud?.updatedAt ?? .distantPast)
      {
        resume = local.position
      }
      guard !Task.isCancelled else { return }
      if duration > 0 && resume / duration > 0.95 { resume = 0 }
      open(resume: resume)
    }
  }
  func open(resume: Double? = nil) {
    prepareTask?.cancel()
    source.close()
    player.pause()
    ready = false
    loading = true
    failure = nil
    let token = UUID()
    generation = token
    seekTarget = resume ?? position
    prepareTask = Task {
      do {
        let url: URL
        if let file = request?.offline?.file {
          url = file
        } else {
          guard let torrent = choices.first(where: { $0.quality == quality }) else {
            throw PlaybackService.Failure.unsupportedVideo
          }
          url = try await source.open(hash: torrent.hash)
        }
        guard generation == token, !Task.isCancelled else { return }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 8
        itemObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
          Task { @MainActor in
            guard let self, self.generation == token else { return }
            if item.status == .failed {
              self.failure = "Please try again or choose another quality in Settings."
              self.loading = false
              self.wantsPlay = false
              self.updateSleep()
            } else if item.status == .readyToPlay {
              self.ready = true
              self.loading = false
              let seconds = item.duration.seconds
              if seconds.isFinite, seconds > 0 { self.duration = seconds }
              if self.seekTarget > 0 {
                let target = min(self.seekTarget, max(0, self.duration - 1))
                self.seekTarget = 0
                await self.player.seek(
                  to: CMTime(seconds: target, preferredTimescale: 600),
                  toleranceBefore: CMTime(seconds: 0.3, preferredTimescale: 600),
                  toleranceAfter: CMTime(seconds: 0.3, preferredTimescale: 600))
              }
              guard self.generation == token else { return }
              if self.wantsPlay { self.player.playImmediately(atRate: self.rate) }
            }
          }
        }
        player.replaceCurrentItem(with: item)
        if !offline {
          setSubtitle(UserDefaults.standard.string(forKey: "desktopSubtitle") ?? "off")
        } else if !subtitleChoices.isEmpty {
          setSubtitle(subtitleChoices.contains("en") ? "en" : subtitleChoices[0])
        }
      } catch is CancellationError {} catch {
        guard generation == token else { return }
        loading = false
        failure = error.localizedDescription
        wantsPlay = false
        updateSleep()
      }
    }
  }
  func toggle() {
    guard ready else { return }
    if wantsPlay {
      wantsPlay = false
      player.pause()
      save()
    } else {
      wantsPlay = true
      if position >= duration - 0.5 { seek(0) }
      player.playImmediately(atRate: rate)
    }
    updateSleep()
  }
  func seek(_ seconds: Double) {
    guard ready, seconds.isFinite else { return }
    position = min(max(0, seconds), max(0, duration - 0.2))
    player.seek(
      to: CMTime(seconds: position, preferredTimescale: 600),
      toleranceBefore: CMTime(seconds: 0.4, preferredTimescale: 600),
      toleranceAfter: CMTime(seconds: 0.4, preferredTimescale: 600)
    ) { [weak self] finished in
      Task { @MainActor in
        if let self, finished {
          if self.wantsPlay { self.player.playImmediately(atRate: self.rate) }
          self.save()
        }
      }
    }
  }
  func setQuality(_ value: String) {
    guard value != quality, !offline else { return }
    save()
    quality = value
    open(resume: position)
  }
  func setSpeed(_ value: Float) {
    rate = value
    if wantsPlay && ready { player.rate = value }
  }
  func setVolume(_ value: Float) {
    volume = value
    player.volume = value
    if value > 0 { volumeBeforeMute = value }
  }
  func toggleMute() {
    setVolume(volume > 0 ? 0 : volumeBeforeMute)
  }
  func setSubtitle(_ code: String) {
    subtitleTask?.cancel()
    subtitle = code
    cues = []
    caption = ""
    subtitleError = nil
    actualSubtitle = code
    guard code != "off" else { return }
    if !offline { UserDefaults.standard.set(code, forKey: "desktopSubtitle") }
    subtitleTask = Task {
      do {
        let text: String
        if let offline = request?.offline {
          guard let url = offline.subtitles[code] else { return }
          text = try String(contentsOf: url, encoding: .utf8)
        } else {
          guard let imdb = request?.movie.imdbCode else { return }
          let track = try await source.subtitles(imdb: imdb, language: code)
          text = track.text
          guard !Task.isCancelled else { return }
          actualSubtitle = track.language
        }
        guard !Task.isCancelled else { return }
        cues = SubtitleParser.parse(text)
        if cues.isEmpty { subtitleError = "Subtitles are unavailable for this movie." }
      } catch { if !Task.isCancelled { subtitleError = "Subtitles are unavailable right now." } }
    }
  }
  private func updateTime() {
    let seconds = player.currentTime().seconds
    if seconds.isFinite { position = max(0, seconds) }
    let length = player.currentItem?.duration.seconds ?? 0
    if length.isFinite, length > 0 { duration = length }
    caption = cues.first(where: { $0.start <= position && $0.end > position })?.text ?? ""
    if duration > 0, position >= duration - 0.2 {
      wantsPlay = false
      player.pause()
      save()
      updateSleep()
    }
    if Date().timeIntervalSince(lastSave) > 15, position > 0, ready { save() }
  }
  func save() {
    guard ready, position > 0, duration > 0 else { return }
    lastSave = Date()
    checkpoint?(position, duration)
  }
  private func updateSleep() {
    if wantsPlay && failure == nil && sleepAssertion == 0 {
      IOPMAssertionCreateWithName(
        kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Watching a movie in Mirror" as CFString, &sleepAssertion)
    } else if !wantsPlay || failure != nil, sleepAssertion != 0 {
      IOPMAssertionRelease(sleepAssertion)
      sleepAssertion = 0
    }
  }
  func stop() {
    save()
    generation = UUID()
    prepareTask?.cancel()
    subtitleTask?.cancel()
    source.close()
    player.pause()
    player.replaceCurrentItem(with: nil)
    if let tick { player.removeTimeObserver(tick) }
    tick = nil
    observations = []
    itemObservation = nil
    if let url = request?.offline?.file { DownloadStore.shared.releasePlaybackFile(url) }
    if sleepAssertion != 0 {
      IOPMAssertionRelease(sleepAssertion)
      sleepAssertion = 0
    }
  }
}

private final class DesktopVideoNSView: NSView {
  let video = AVPlayerLayer()
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    layer?.addSublayer(video)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layout() {
    super.layout()
    video.frame = bounds
  }
}
private struct DesktopVideoSurface: NSViewRepresentable {
  let player: AVPlayer
  func makeNSView(context: Context) -> DesktopVideoNSView {
    let view = DesktopVideoNSView()
    view.video.player = player
    view.video.videoGravity = .resizeAspect
    return view
  }
  func updateNSView(_ view: DesktopVideoNSView, context: Context) { view.video.player = player }
  static func dismantleNSView(_ view: DesktopVideoNSView, coordinator: ()) {
    view.video.player = nil
  }
}

struct DesktopPlayerView: View {
  @Environment(DesktopSession.self) private var session
  @Environment(\.modelContext) private var context
  @State private var model = DesktopPlayerController()
  @State private var controls = true
  @State private var settings = false
  @State private var hideTask: Task<Void, Never>?
  @State private var enteredFullscreen = false
  @State private var isFullscreen = false
  @State private var scrubbing = false
  @State private var scrubPosition: Double = 0
  @State private var window: NSWindow?
  var body: some View {
    ZStack {
      Color.black
      DesktopVideoSurface(player: model.player)
        .onTapGesture { if model.playing { controls.toggle() } else { reveal() } }
        .onContinuousHover { _ in reveal() }
      if !model.caption.isEmpty {
        VStack {
          Spacer()
          Text(model.caption).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
            .multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 20).padding(
              .vertical, 6
            )
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 5)).shadow(
              color: .black, radius: 2
            )
            .frame(maxWidth: 850)
        }.padding(.bottom, controls ? 144 : 55).padding(.horizontal, 65).allowsHitTesting(false)
      }
      if controls || model.loading || !model.playing || model.failure != nil {
        chrome.transition(.opacity)
      }
    }.foregroundStyle(.white).ignoresSafeArea().background(.black)
      .toolbar(.hidden, for: .windowToolbar)
      .onContinuousHover { _ in reveal() }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification))
    { _ in model.stop() }
      .onExitCommand {
        if window?.styleMask.contains(.fullScreen) == true {
          window?.toggleFullScreen(nil)
        } else {
          close()
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .mirrorPlayPause)) { _ in
        model.toggle()
        reveal()
      }
      .onReceive(NotificationCenter.default.publisher(for: .mirrorSkipForward)) { _ in
        model.seek(model.position + 10)
        reveal()
      }
      .onReceive(NotificationCenter.default.publisher(for: .mirrorSkipBackward)) { _ in
        model.seek(model.position - 10)
        reveal()
      }
      .onReceive(NotificationCenter.default.publisher(for: .mirrorFullscreen)) { _ in fullscreen() }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification))
    { note in
      if let changedWindow = note.object as? NSWindow, changedWindow === window {
        isFullscreen = true
      }
    }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification))
    { note in
      if let changedWindow = note.object as? NSWindow, changedWindow === window {
        isFullscreen = false
      }
    }
      .onChange(of: model.playing) { _, _ in reveal() }
      .onChange(of: model.buffering) { _, _ in reveal() }
      .task {
        guard let request = session.playback else { return }
        model.checkpoint = { position, duration in
          WatchHistorySync.saveLocal(
            context: context, movie: request.movie, position: position, duration: duration)
          FirestoreService.shared.savePlaybackProgress(
            movieId: request.movie.id, title: request.movie.title,
            posterURL: request.movie.posterURL?.absoluteString, positionSeconds: position,
            durationSeconds: duration, year: request.movie.year, genres: request.movie.genres ?? [],
            backdropURL: request.movie.backdropURL?.absoluteString)
          if request.offline != nil {
            DownloadStore.shared.updatePlayback(
              id: request.movie.id, position: position, duration: duration)
          }
        }
        model.start(request)
        window = NSApp.keyWindow ?? NSApp.windows.first
        isFullscreen = window?.styleMask.contains(.fullScreen) == true
        window?.toolbar?.isVisible = false
        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        if window?.styleMask.contains(.fullScreen) == false {
          enteredFullscreen = true
          window?.toggleFullScreen(nil)
        }
      }
      .onDisappear {
        hideTask?.cancel()
        model.stop()
        if enteredFullscreen, window?.styleMask.contains(.fullScreen) == true {
          window?.toggleFullScreen(nil)
        }
      }
  }
  private var chrome: some View {
    ZStack {
      LinearGradient(
        colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.78)], startPoint: .top,
        endPoint: .bottom
      ).allowsHitTesting(false)
      VStack(spacing: 0) {
        HStack {
          playerButton(.arrowLeft, "Back to Mirror", close)
          Spacer()
          VStack(spacing: 5) {
            Text(session.playback?.movie.title ?? "").font(.system(size: 18, weight: .semibold))
              .lineLimit(1)
            Text(model.qualityLabel).font(.system(size: 12)).foregroundStyle(.white.opacity(0.58))
          }
          Spacer()
          playerButton(.settingLinear, "Playback settings") {
            settings.toggle()
            reveal()
          }
          .popover(isPresented: $settings) { playerSettings }
        }.padding(.horizontal, 40).padding(.top, 34)
        Spacer()
        if let failure = model.failure {
          VStack(spacing: 18) {
            Text("Unable to play this movie").font(.title2.weight(.medium))
            Text(failure).font(.callout).foregroundStyle(.white.opacity(0.6))
              .multilineTextAlignment(.center).frame(maxWidth: 500)
            Button {
              model.wantsPlay = true
              model.open(resume: model.position)
            } label: {
              Text("Try again").foregroundStyle(.black).padding(.horizontal, 30).padding(
                .vertical, 13
              ).background(.white, in: Capsule())
            }.buttonStyle(.plain)
          }
        } else if model.loading || model.buffering {
          ProgressView().controlSize(.large).tint(.white).frame(height: 80)
        } else {
          HStack(spacing: 55) {
            playerButton(.backward10, "Back 10 seconds") {
              model.seek(model.position - 10)
              reveal()
            }
            Button {
              model.toggle()
              reveal()
            } label: {
              PhosphorView(model.wantsPlay ? .pauseLinear : .playBold, size: 30, color: .black)
                .frame(width: 76, height: 76).background(.white, in: Circle())
            }.buttonStyle(.plain).help("Play / Pause · Space")
            playerButton(.forward10, "Forward 10 seconds") {
              model.seek(model.position + 10)
              reveal()
            }
          }
        }
        Spacer()
        if model.ready && model.failure == nil {
          VStack(spacing: 18) {
            HStack(spacing: 15) {
              Text(time(scrubbing ? scrubPosition : model.position)).monospacedDigit().frame(
                width: 65)
              Slider(
                value: Binding(
                  get: { scrubbing ? scrubPosition : model.position }, set: { scrubPosition = $0 }),
                in: 0...max(1, model.duration)
              ) { editing in
                if editing {
                  scrubbing = true
                  scrubPosition = model.position
                  hideTask?.cancel()
                } else {
                  scrubbing = false
                  model.seek(scrubPosition)
                  reveal()
                }
              }.tint(.white).help("Seek")
              Text(time(model.duration)).monospacedDigit().frame(width: 65)
            }.font(.system(size: 12))
            HStack(spacing: 14) {
              playerButton(
                model.volume == 0
                  ? .speakerMuted : (model.volume < 0.5 ? .speakerLow : .speakerHigh),
                model.volume == 0 ? "Unmute" : "Mute"
              ) {
                model.toggleMute()
                reveal()
              }
              Slider(
                value: Binding(get: { Double(model.volume) }, set: { model.setVolume(Float($0)) }),
                in: 0...1
              ).frame(width: 100).tint(.white).help("Volume").accessibilityLabel("Volume")
              Spacer()
              if model.actualSubtitle != "off" {
                Text(SubtitleLanguage.name(model.actualSubtitle)).font(.caption).foregroundStyle(
                  .white.opacity(0.65))
              }
              playerButton(
                isFullscreen ? .fullscreenExit : .fullscreenEnter,
                isFullscreen ? "Exit full screen · F" : "Enter full screen · F", fullscreen)
            }
          }.padding(.horizontal, 45).padding(.bottom, 30)
        } else {
          Color.clear.frame(height: 95)
        }
      }
    }
  }
  private var playerSettings: some View {
    VStack(alignment: .leading, spacing: 19) {
      Text("Playback settings").font(.headline)
      if model.offline {
        HStack {
          Text("Video quality")
          Spacer()
          Text(model.qualityLabel).foregroundStyle(Color.mirrorTextSecondary)
        }
      } else {
        Picker(
          "Video quality", selection: Binding(get: { model.quality }, set: { model.setQuality($0) })
        ) { ForEach(model.choices) { Text(MovieQuality.label($0.quality)).tag($0.quality) } }
      }
      Picker("Playback speed", selection: Binding(get: { model.rate }, set: { model.setSpeed($0) }))
      {
        ForEach([Float(0.5), 1, 1.25, 1.5, 2], id: \.self) {
          Text(String(format: "%gx", $0)).tag($0)
        }
      }
      HStack {
        Text("Audio")
        Spacer()
        Text(
          session.playback?.movie.language.flatMap {
            Locale.current.localizedString(forLanguageCode: $0)
          } ?? "Original"
        ).foregroundStyle(Color.mirrorTextSecondary)
      }
      Picker(
        "Subtitles", selection: Binding(get: { model.subtitle }, set: { model.setSubtitle($0) })
      ) {
        Text("Off").tag("off")
        ForEach(model.subtitleChoices, id: \.self) { Text(SubtitleLanguage.name($0)).tag($0) }
      }
      if let error = model.subtitleError {
        Text(error).font(.caption).foregroundStyle(Color.mirrorTextSecondary)
      }
    }.pickerStyle(.menu).padding(23).frame(width: 350).background(Color.mirrorSurface1)
      .foregroundStyle(Color.mirrorInk)
      .onDisappear { reveal() }
  }
  private func playerButton(_ icon: PhosphorIcon, _ title: String, _ action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      PhosphorView(icon, size: 25, color: .white).frame(width: 42, height: 42).contentShape(
        Rectangle())
    }.buttonStyle(.plain).help(title).accessibilityLabel(title)
  }
  private func reveal() {
    controls = true
    hideTask?.cancel()
    guard model.playing, !model.buffering, !settings, !scrubbing else { return }
    hideTask = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled, model.playing, !model.buffering, !settings, !scrubbing {
        withAnimation(.easeOut(duration: 0.2)) { controls = false }
      }
    }
  }
  private func fullscreen() {
    window?.toggleFullScreen(nil)
    reveal()
  }
  private func close() {
    model.save()
    session.playback = nil
  }
  private func time(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "00:00" }
    let seconds = Int(value)
    return seconds >= 3600
      ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
      : String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}
