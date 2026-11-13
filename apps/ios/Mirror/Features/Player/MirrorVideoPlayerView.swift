import SwiftUI
import AVKit
import SwiftData
import OSLog

public struct MirrorVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    let movie: MovieDetail
    let resumePosition: Double?
    let offline: OfflineMovie?
    private let requestedAt: ContinuousClock.Instant
    @State private var pendingResume: Double = 0
    @State private var resumeLookup: Task<Void, Never>?
    @State private var initialPositionChosen = false
    @State private var hasConfirmedPosition = false
    @State private var isPreparing = true
    @State private var hasReadyFrame = false
    @State private var hasEnded = false
    @GestureState private var scrubPreview: Double?
    @State private var seekTarget: Double?
    @State private var seekID = UUID()
    @State private var recoveryTask: Task<Void, Never>?
    @State private var recoveryUsed = false
    @State private var resumeInForeground = false
    @State private var lastLocalSave: Double?
    @State private var lastCloudSave: Double?
    @StateObject private var videoSurface = PlayerVideoSurface()
    @State private var startupStarted: ContinuousClock.Instant?
    @State private var seekStarted: ContinuousClock.Instant?
    @State private var stallStarted: ContinuousClock.Instant?
    @State private var recoveryStarted: ContinuousClock.Instant?
    #if DEBUG
    @State private var seekFrameProbe: Task<Void, Never>?
    #endif
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mirror.app", category: "Playback")
    private var timelinePosition: Double { scrubPreview ?? seekTarget ?? currentTime }
    private var showsLoadingOverlay: Bool { isPreparing || !hasReadyFrame }

    @State private var playbackService = PlaybackService()
    @State private var playbackTask: Task<Void, Never>?
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?
    @State private var playbackStatus: NSKeyValueObservation?
    @State private var isBuffering = true
    @State private var bufferedRanges: [ClosedRange<Double>] = []
    @State private var playerStatus: NSKeyValueObservation?
    @State private var bufferObservation: NSKeyValueObservation?
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0.0
    @State private var totalDuration: Double = 7200.0
    @State private var showControls: Bool = true
    @State private var isLocked: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var errorMessage: String? = nil

    // Player settings state
    @State private var selectedSpeed: Float = 1.0
    @State private var selectedQuality: String = "Full HD 1080"
    @State private var selectedSubtitle: String = "English"
    @State private var subtitleTask: Task<Void, Never>?
    @State private var subtitleCues: [SubtitleCue] = []
    @State private var subtitleStatus: String?

    @State private var controlsTimer: Timer?


    public init(movie: MovieDetail, resumePosition: Double? = nil, requestedAt: ContinuousClock.Instant = .now) {
        self.requestedAt = requestedAt
        self.resumePosition = resumePosition
        self.movie = movie
        self.offline = nil
        let qualities = Self.streamingQualities(for: movie)
        _selectedQuality = State(initialValue: qualities.contains("Full HD 1080") ? "Full HD 1080" : (qualities.first ?? "Full HD 1080"))
    }

    init(download: OfflineMovie, requestedAt: ContinuousClock.Instant = .now) {
        self.requestedAt = requestedAt
        movie = download.movie; resumePosition = download.position; offline = download
        _selectedQuality = State(initialValue: download.quality)
        let codes = SubtitleLanguage.codes.filter { download.subtitles[$0] != nil }
        _selectedSubtitle = State(initialValue: codes.first.map(SubtitleLanguage.name) ?? "Off")
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                // 1. AVPlayer Video Surface
                if let player = player {
                    VideoPlayerView(player: player, surface: videoSurface) { firstFrameReady(for: player) }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityRepresentation {
                            Button(showControls ? "Hide playback controls" : "Show playback controls") {
                                toggleControls()
                            }
                        }
                        .accessibilityHidden(showsLoadingOverlay)
                }

                if showsLoadingOverlay {
                    connectingOverlay
                }

                if videoSurface.isInPictureInPicture {
                    Text("Playing in Picture in Picture")
                        .foregroundStyle(Color.mirrorTextSecondary)
                        .allowsHitTesting(false)
                }

                if !showsLoadingOverlay,
                   let caption = subtitleCues.first(where: { currentTime >= $0.start && currentTime < $0.end })?.text {
                    VStack {
                        Spacer()
                        Text(caption).font(.mirrorBody)
                            .foregroundStyle(Color.mirrorInk).multilineTextAlignment(.center)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 70).padding(.bottom, showControls ? 110 : 26)
                    }
                    .allowsHitTesting(false)
                }

                // 2. Lock State Indicator (When locked)
                if isLocked && showControls && !showsLoadingOverlay {
                    VStack {
                        Spacer()
                        Button(action: {
                            HapticManager.shared.notification(.success)
                            isLocked = false
                            resetControlsTimer()
                        }) {
                            HStack(spacing: 8) {
                                PhosphorView(.lockLinear, size: 16, color: Color.mirrorOnInk)
                                Text("Unlock Screen")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.mirrorOnInk)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.mirrorInk)
                            .clipShape(Capsule())
                        }
                        .padding(.bottom, 40)
                    }
                }

                // 3. Normal Controls Overlay (Behance Board 17)
                // Always keep top controls accessible while connecting so user is never trapped
                if showsLoadingOverlay || (!isLocked && (showControls || !isPlaying || isBuffering)) {
                    ZStack {
                        if !showsLoadingOverlay {
                            // Subtle dark vignette for readability during video playback
                            Color.black.opacity(0.4).ignoresSafeArea()
                                .allowsHitTesting(false)
                        }

                        VStack {
                            // Top Bar (Behance Board 17)
                            topControlsBar

                            Spacer()

                            if !showsLoadingOverlay {
                                // Center Transport Controls (10s Rewind, Play/Pause, 10s Forward)
                                centerTransportControls

                                Spacer()

                                // Bottom Controls (Movie scrubber and screen lock)
                                bottomControlsBar
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(PlayerOrientationBridge())
        .tint(Color.mirrorInk)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $isShowingSettings) {
            PlayerSettingsSheet(
                selectedSpeed: $selectedSpeed,
                selectedQuality: $selectedQuality,
                selectedSubtitle: $selectedSubtitle,
                qualities: availableQualities,
                subtitleStatus: subtitleStatus,
                subtitleOptions: subtitleOptions
            )
        }
        .onChange(of: selectedSubtitle) { _, _ in loadSubtitles() }
        .onChange(of: isBuffering) { _, _ in updateControlsVisibility() }
        .onChange(of: showsLoadingOverlay) { _, _ in updateControlsVisibility() }
        .onChange(of: isPlaying) { _, _ in updateControlsVisibility() }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification).receive(on: DispatchQueue.main)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            finishPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification).receive(on: DispatchQueue.main)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            recoverPlayback(message: "Playback was interrupted.")
        }
        .alert("Picture in Picture couldn’t start", isPresented: Binding(
            get: { videoSurface.pictureInPictureError },
            set: { if !$0 { videoSurface.dismissPictureInPictureError() } }
        )) { Button("OK") { videoSurface.dismissPictureInPictureError() } }
        .onChange(of: isShowingSettings) { _, _ in updateControlsVisibility() }
        .onChange(of: scrubPreview == nil) { _, ended in
            if ended { resetControlsTimer() }
        }
        .onChange(of: selectedSpeed) { _, newSpeed in
            player?.defaultRate = newSpeed
            if isPlaying, !isPreparing, seekTarget == nil { player?.play() }
        }
        .onChange(of: selectedQuality) { _, _ in
            guard offline == nil else { return }
            restartPlayback()
        }
        .onAppear {
            if let offline { DownloadStore.shared.retainPlaybackFile(offline.file) }
            startupStarted = requestedAt
            isPlaying = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true
            setupAudioSession()
            prepareInitialPosition()
            if movie.runtime > 0 {
                totalDuration = Double(movie.runtime * 60)
            }
            startPlayback()
            loadSubtitles()
        }
        .onDisappear {
            subtitleTask?.cancel()
            resumeLookup?.cancel()
            playbackTask?.cancel()
            saveProgress(flush: true)
            controlsTimer?.invalidate()
            tearDownPlayer()
            playbackService.close()
        }
    }

    // MARK: - Connecting Placeholder Overlay
    private var connectingOverlay: some View {
        ZStack {
            Color.black
            VStack(spacing: 18) {
                if errorMessage != nil {
                    Text("Unable to play this movie")
                        .font(.system(size: 18, weight: .medium)).foregroundStyle(Color.mirrorInk)
                    Text(errorMessage ?? "Please try again in a moment or choose another quality.")
                        .font(.system(size: 14)).foregroundStyle(Color.mirrorTextSecondary)
                    Button("Try again") { restartPlayback() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mirrorOnInk).padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Color.mirrorInk, in: Capsule())
                } else {
                    ProgressView()
                        .tint(Color.mirrorInk)
                        .scaleEffect(1.2)
                        .accessibilityLabel("Loading movie…")
                }
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Top Controls Bar
    private var topControlsBar: some View {
        HStack(alignment: .center) {
            // Back Chevron & PiP Button
            HStack(spacing: 16) {
                Button(action: {
                    dismiss()
                }) {
                    PhosphorView(.arrowLeft, size: 20, color: Color.mirrorInk)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close player")

                Button { videoSurface.togglePictureInPicture() } label: {
                    PhosphorView(.maximizeCircle, size: 20, color: Color.mirrorInk)
                        .frame(width: 44, height: 44)
                        .opacity(videoSurface.canStartPictureInPicture || videoSurface.isInPictureInPicture ? 1 : 0.35)
                }
                .disabled(showsLoadingOverlay || (!videoSurface.canStartPictureInPicture && !videoSurface.isInPictureInPicture))
                .opacity(showsLoadingOverlay ? 0 : 1)
                .accessibilityHidden(showsLoadingOverlay)
                .accessibilityLabel(videoSurface.isInPictureInPicture ? "Stop Picture in Picture" : "Picture in Picture")
            }

            Spacer()

            // Movie Title & Streaming Info (Behance Board 17)
            VStack(spacing: 2) {
                Text(movie.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.mirrorInk)
                    .lineLimit(1)

                Text(selectedQuality)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.mirrorInk.opacity(0.55))
            }

            Spacer()

            // AirPlay & Settings Gear
            HStack(spacing: 18) {
                Group {
                    #if targetEnvironment(simulator)
                    PhosphorView(.screenmirroring, size: 20, color: Color.mirrorInk.opacity(0.35))
                        .accessibilityLabel("AirPlay unavailable")
                    #else
                    PlayerAirPlayPicker()
                    #endif
                }
                .frame(width: 44, height: 44)
                .allowsHitTesting(!showsLoadingOverlay)
                .opacity(showsLoadingOverlay ? 0 : 1)
                .accessibilityHidden(showsLoadingOverlay)

                Button(action: {
                    HapticManager.shared.selection()
                    isShowingSettings = true
                }) {
                    PhosphorView(.settingLinear, size: 20, color: Color.mirrorInk)
                }
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Center Transport Controls (Behance Board 17)
    private var centerTransportControls: some View {
        HStack(spacing: 64) {
            // Seek -10s
            Button(action: {
                HapticManager.shared.selection()
                seek(by: -10)
                resetControlsTimer()
            }) {
                PhosphorView(.backward10, size: 36, color: Color.mirrorInk)
            }

            // Big Solid White Circle Play/Pause Button
            Button(action: {
                HapticManager.shared.impact(.medium)
                togglePlayPause()
                resetControlsTimer()
            }) {
                Circle()
                    .fill(Color.mirrorInk)
                    .frame(width: 64, height: 64)
                    .overlay(
                        PhosphorView(hasEnded ? .rotateLeft : (isPlaying ? .pauseLinear : .playBold), size: 26, color: Color.mirrorOnInk)
                    )
            }
            .accessibilityLabel(hasEnded ? "Replay" : (isPlaying ? "Pause" : "Play"))

            // Seek +10s
            Button(action: {
                HapticManager.shared.selection()
                seek(by: 10)
                resetControlsTimer()
            }) {
                PhosphorView(.forward10, size: 36, color: Color.mirrorInk)
            }
        }
    }

    // MARK: - Bottom Controls Bar (Behance Board 17)
    private var bottomControlsBar: some View {
        VStack(spacing: 12) {
            // Scrubber Bar with Time Labels
            HStack(spacing: 12) {
                Text(formatTime(timelinePosition))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.mirrorInk)

                GeometryReader { geometry in
                    let width = geometry.size.width
                    let progress = fraction(of: timelinePosition)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.mirrorInk.opacity(0.24))
                            .frame(height: 4)

                        ForEach(bufferedRanges, id: \.self) { range in
                            let start = fraction(of: range.lowerBound)
                            let end = fraction(of: range.upperBound)
                            Capsule()
                                .fill(Color.mirrorTextTertiary)
                                .frame(width: width * (end - start), height: 4)
                                .offset(x: width * start)
                        }

                        Capsule()
                            .fill(Color.mirrorInk)
                            .frame(width: width * progress, height: 4)

                        Circle()
                            .fill(Color.mirrorInk)
                            .frame(width: 14, height: 14)
                            .offset(x: max(0, min(width - 14, width * progress - 7)))
                    }
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .updating($scrubPreview) { gesture, preview, _ in
                            guard width > 0 else { return }
                            preview = min(1, max(0, gesture.location.x / width)) * totalDuration
                        }
                        .onChanged { _ in
                            controlsTimer?.invalidate()
                            showControls = true
                        }
                        .onEnded { gesture in
                            guard width > 0 else { return }
                            seek(to: min(1, max(0, gesture.location.x / width)) * totalDuration)
                        }, including: isPreparing ? .none : .all)
                    .accessibilityElement()
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(formatTime(timelinePosition)) of \(formatTime(totalDuration))")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: seek(by: 10)
                        case .decrement: seek(by: -10)
                        @unknown default: break
                        }
                    }
                }
                .frame(height: 32)

                Text(formatTime(totalDuration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.mirrorTextSecondary)
            }

            // Bottom Action Pills (Behance Board 17)
            HStack(spacing: 12) {
                // Block / Lock Touch Gestures Pill (Behance Board 17)
                Button(action: {
                    HapticManager.shared.notification(.success)
                    isLocked = true
                    showControls = !isPlaying || isBuffering
                }) {
                    HStack(spacing: 6) {
                        PhosphorView(.lockLinear, size: 14, color: Color.mirrorInk)
                        Text("Block")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color.mirrorInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.mirrorInk.opacity(0.12))
                    .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Actions & Media Setup

    private func prepareInitialPosition() {
        let uid = AuthService.shared.currentUser?.uid
        let id = movie.id
        let local = uid.flatMap { userID in
            let descriptor = FetchDescriptor<WatchHistoryItem>(predicate: #Predicate {
                $0.movieId == id && $0.userId == userID
            })
            return try? modelContext.fetch(descriptor).first
        }
        if let offline {
            pendingResume = offline.position
            if let local, local.lastWatched > (offline.lastPlayedAt ?? .distantPast) {
                pendingResume = local.progressSeconds
            }
            return
        }

        pendingResume = resumePosition ?? local?.progressSeconds ?? 0
        guard resumePosition == nil, let uid else { return }
        let localDate = local?.lastWatched
        // Use a fresh cloud checkpoint only if it arrives before the first seek.
        resumeLookup = Task { @MainActor in
            guard let checkpoint = try? await FirestoreService.shared.playbackCheckpoint(movieId: id),
                  !Task.isCancelled, !initialPositionChosen,
                  AuthService.shared.currentUser?.uid == uid,
                  localDate == nil || checkpoint.updatedAt > (localDate ?? .distantPast) else { return }
            pendingResume = checkpoint.position
        }
    }

    private func startPlayback() {
        errorMessage = nil
        isPreparing = true
        isBuffering = isPlaying
        if startupStarted == nil { startupStarted = .now }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            if let offline {
                guard FileManager.default.fileExists(atPath: offline.file.path) else {
                    errorMessage = "This downloaded file is missing. Download the movie again."
                    return
                }
                setupPlayer(with: offline.file)
                return
            }
            let candidates = (movie.torrents ?? []).filter { MovieQuality.label($0.quality) == selectedQuality }
            guard let torrent = candidates.max(by: { $0.seeds < $1.seeds }) else {
                errorMessage = "Unavailable quality"
                return
            }
            do {
                let opening = ContinuousClock.now
                let url = try await playbackService.open(hash: torrent.hash)
                try Task.checkCancellation()
                recordTiming("stream_session", since: opening)
                setupPlayer(with: url)
            } catch is CancellationError { } catch {
                if !Task.isCancelled {
                    errorMessage = (error as? PlaybackService.Failure)?.errorDescription
                        ?? "Please try again in a moment or choose another quality."
                }
            }
        }
    }

    private func restartPlayback() {
        recoveryUsed = false
        recoveryStarted = nil
        startupStarted = .now
        reopenPlayback()
    }

    private func reopenPlayback() {
        if hasConfirmedPosition { pendingResume = hasEnded ? 0 : currentTime }
        tearDownPlayer()
        playbackTask?.cancel()
        playbackService.close()
        startPlayback()
    }

    private func setupPlayer(with url: URL) {
        guard player == nil else { return }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.defaultRate = selectedSpeed
        player = avPlayer
        playbackStatus = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            Task { @MainActor in
                guard self.player === player else { return }
                if (videoSurface.isInPictureInPicture || player.isExternalPlaybackActive),
                   !hasEnded, !isPreparing, seekTarget == nil {
                    isPlaying = player.timeControlStatus != .paused
                    if !isPlaying { saveProgress(flush: true) }
                }
                updateBuffering()
            }
        }
        playerStatus = item.observe(\.status, options: [.initial, .new]) { item, _ in
            Task { @MainActor in
                guard player === avPlayer, avPlayer.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    guard isPreparing, seekTarget == nil else { return }
                    initialPositionChosen = true
                    resumeLookup?.cancel()
                    updateDuration(from: item)
                    let target = min(pendingResume, max(0, totalDuration - 1))
                    if target > 0 {
                        performSeek(to: target, player: avPlayer, preparing: true)
                    } else {
                        if !hasEnded { acceptPosition(0) }
                        isPreparing = false
                        if isPlaying { avPlayer.play() }
                        updateBuffering()
                    }
                case .failed:
                    recoverPlayback(message: "The video couldn’t be opened.")
                default: break
                }
            }
        }
        bufferObservation = item.observe(\.loadedTimeRanges, options: [.initial, .new]) { item, _ in
            Task { @MainActor in
                guard player === avPlayer, avPlayer.currentItem === item else { return }
                let ranges: [ClosedRange<Double>] = item.loadedTimeRanges.compactMap { value in
                    let range = value.timeRangeValue
                    let start = range.start.seconds
                    let end = CMTimeRangeGetEnd(range).seconds
                    guard start.isFinite, end.isFinite, end > start else { return nil }
                    return start...end
                }
                if bufferedRanges != ranges { bufferedRanges = ranges }
            }
        }
        observedPlayer = avPlayer
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            guard player === avPlayer, let item = avPlayer.currentItem else { return }
            updateDuration(from: item)
            guard !isPreparing, seekTarget == nil, !hasEnded, time.seconds.isFinite else { return }
            acceptPosition(time.seconds)
            if avPlayer.timeControlStatus == .playing { saveProgress() }
        }
        updateBuffering()
    }

    private func tearDownPlayer() {
        #if DEBUG
        seekFrameProbe?.cancel()
        seekFrameProbe = nil
        #endif
        endStall()
        recoveryTask?.cancel()
        recoveryTask = nil
        playbackStatus = nil
        playerStatus = nil
        bufferObservation = nil
        if let timeObserver, let observedPlayer { observedPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observedPlayer = nil
        seekID = UUID()
        seekTarget = nil
        seekStarted = nil
        player?.currentItem?.cancelPendingSeeks()
        player?.pause()
        videoSurface.detach()
        player = nil
        hasReadyFrame = false
        bufferedRanges = []
    }

    private func togglePlayPause() {
        guard let player else { return }
        if hasEnded {
            hasEnded = false
            isPlaying = true
            seek(to: 0)
        } else if isPlaying {
            isPlaying = false
            player.pause()
            saveProgress(flush: true)
        } else {
            isPlaying = true
            if !isPreparing, seekTarget == nil { player.play() }
        }
        updateBuffering()
    }

    private func seek(by seconds: Double) {
        seek(to: (seekTarget ?? currentTime) + seconds)
    }

    private func seek(to seconds: Double) {
        guard let player, !isPreparing, seconds.isFinite else { return }
        hasEnded = false
        seekStarted = .now
        performSeek(to: min(totalDuration, max(0, seconds)), player: player, preparing: false)
    }

    private func performSeek(to seconds: Double, player: AVPlayer, preparing: Bool) {
        let id = UUID()
        seekID = id
        seekTarget = seconds
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        #if DEBUG
        if !preparing, let started = seekStarted {
            measureSeekFrame(player: player, seekID: id, since: started)
        }
        #endif
        updateBuffering()
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)) { finished in
            Task { @MainActor in
                guard self.player === player, seekID == id else { return }
                seekTarget = nil
                guard finished else {
                    recoverPlayback(message: "Couldn’t seek to that position.")
                    return
                }
                if player.currentTime().seconds.isFinite { acceptPosition(player.currentTime().seconds) }
                if preparing { isPreparing = false }
                if !preparing, currentTime >= totalDuration {
                    finishPlayback()
                    return
                }
                if isPlaying { player.play() }
                updateBuffering()
                if !isPlaying { saveProgress(flush: true) }
            }
        }
    }

    private func finishPlayback() {
        guard !hasEnded else { return }
        hasEnded = true
        isPlaying = false
        isPreparing = false
        seekID = UUID()
        seekTarget = nil
        seekStarted = nil
        isLocked = false
        acceptPosition(totalDuration)
        saveProgress(flush: true)
        updateBuffering()
    }

    private func updateDuration(from item: AVPlayerItem) {
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0, totalDuration != duration { totalDuration = duration }
    }

    private func acceptPosition(_ position: Double) {
        guard position.isFinite else { return }
        currentTime = max(0, min(totalDuration, position))
        if !hasConfirmedPosition {
            lastLocalSave = currentTime
            lastCloudSave = currentTime
            hasConfirmedPosition = true
        }
    }

    private func fraction(of position: Double) -> CGFloat {
        CGFloat(min(1, max(0, position / max(totalDuration, 0.001))))
    }

    private func updateBuffering() {
        let waiting = !hasEnded && (isPreparing || seekTarget != nil || (isPlaying && player?.timeControlStatus != .playing))
        isBuffering = waiting
        if let started = seekStarted, seekTarget == nil, !isPreparing, !waiting {
            recordTiming(isPlaying ? "seek_to_playing" : "seek_completed_paused", since: started)
            seekStarted = nil
        }
        if !waiting {
            if let started = recoveryStarted, player?.timeControlStatus == .playing {
                recordTiming("recovery_to_playing", since: started)
                recoveryStarted = nil
            }
            endStall()
            recoveryTask?.cancel()
            recoveryTask = nil
            return
        }
        if startupStarted == nil, seekStarted == nil, stallStarted == nil { stallStarted = .now }
        guard offline == nil, let player else { return }
        guard scenePhase != .background || videoSurface.isInPictureInPicture || player.isExternalPlaybackActive else {
            recoveryTask?.cancel()
            recoveryTask = nil
            return
        }
        guard recoveryTask == nil else { return }
        recoveryTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(isPreparing ? 30 : 15)) }
            catch { return }
            guard self.player === player, isBuffering else { return }
            recoverPlayback(message: "The stream stopped responding.")
        }
    }

    private func recoverPlayback(message: String) {
        if offline == nil, !recoveryUsed {
            recoveryUsed = true
            recoveryStarted = .now
            Self.log.info("Retrying stream from last confirmed position")
            reopenPlayback()
        } else {
            tearDownPlayer()
            playbackService.close()
            isBuffering = false
            errorMessage = offline == nil ? message : "This downloaded video couldn’t be played."
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .background {
            saveProgress(flush: true)
            guard !videoSurface.isInPictureInPicture, player?.isExternalPlaybackActive != true else { return }
            resumeInForeground = isPlaying
            isPlaying = false
            player?.pause()
            updateBuffering()
        } else if phase == .active {
            if resumeInForeground {
                resumeInForeground = false
                isPlaying = true
                if !isPreparing, seekTarget == nil { player?.play() }
            }
            updateBuffering()
        }
    }

    private func firstFrameReady(for player: AVPlayer) {
        guard self.player === player else { return }
        hasReadyFrame = true
        guard let started = startupStarted else { return }
        recordTiming("first_frame", since: started)
        startupStarted = nil
    }

    #if DEBUG
    /// Opt-in frame sampling for benchmarks. Normal playback uses the transport timings.
    private func measureSeekFrame(player: AVPlayer, seekID: UUID, since start: ContinuousClock.Instant) {
        seekFrameProbe?.cancel()
        guard ProcessInfo.processInfo.arguments.contains("--measure-playback-frames"),
              !player.isExternalPlaybackActive, !videoSurface.isInPictureInPicture,
              let item = player.currentItem else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(output)
        seekFrameProbe = Task { @MainActor in
            defer { item.remove(output) }
            let deadline = start.advanced(by: .seconds(35))
            while !Task.isCancelled, self.player === player, self.seekID == seekID, ContinuousClock.now < deadline {
                if seekTarget == nil, output.hasNewPixelBuffer(forItemTime: player.currentTime()) {
                    recordTiming("seek_frame_ready", since: start)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
            }
        }
    }
    #endif

    private func endStall() {
        if let started = stallStarted { recordTiming("stall", since: started) }
        stallStarted = nil
    }

    private func recordTiming(_ event: String, since start: ContinuousClock.Instant) {
        let elapsed = start.duration(to: .now).components
        let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        let downloading = DownloadStore.shared.records.contains { $0.status == .downloading || $0.status == .preparing }
        Self.log.info("\(event, privacy: .public) ms=\(milliseconds) offline=\(offline != nil) download_active=\(downloading) quality=\(selectedQuality, privacy: .public)")
    }

    private func toggleControls() {
        if showsLoadingOverlay || !isPlaying || isBuffering {
            showControls = true
        } else {
            withAnimation { showControls.toggle() }
            if showControls, !isLocked { resetControlsTimer() }
        }
    }

    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        guard !showsLoadingOverlay, isPlaying, !isBuffering, scrubPreview == nil, seekTarget == nil, player?.timeControlStatus == .playing, !isShowingSettings else {
            showControls = true
            return
        }
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            guard !showsLoadingOverlay, isPlaying, !isBuffering, scrubPreview == nil, seekTarget == nil, player?.timeControlStatus == .playing, !isShowingSettings else { return }
            withAnimation { showControls = false }
        }
    }

    private func updateControlsVisibility() {
        controlsTimer?.invalidate()
        showControls = true
        resetControlsTimer()
    }

    private var availableQualities: [String] {
        if let offline { return [offline.quality] }
        return Self.streamingQualities(for: movie)
    }

    private static func streamingQualities(for movie: MovieDetail) -> [String] {
        MovieQuality.choices(movie.torrents ?? []).map { MovieQuality.label($0.quality) }
    }

    private var subtitleOptions: [String] {
        guard let offline else { return ["Off"] + SubtitleLanguage.codes.map(SubtitleLanguage.name) }
        return ["Off"] + SubtitleLanguage.codes.filter { offline.subtitles[$0] != nil }.map(SubtitleLanguage.name)
    }

    private func loadSubtitles() {
        subtitleTask?.cancel()
        subtitleCues = []
        let requested = selectedSubtitle
        guard requested != "Off" else { subtitleStatus = nil; return }
        if let offline {
            if let code = SubtitleLanguage.code(requested), let url = offline.subtitles[code], let text = try? String(contentsOf: url, encoding: .utf8) {
                subtitleCues = SubtitleParser.parse(text)
                subtitleStatus = subtitleCues.isEmpty ? "Downloaded subtitles couldn’t be read." : nil
            } else { subtitleStatus = "These subtitles aren’t downloaded on this device." }
            return
        }
        subtitleStatus = "Loading subtitles…"
        let languages = ["English": "en", "Italian": "it", "Spanish": "es", "French": "fr"]
        subtitleTask = Task { @MainActor in
            do {
                let track = try await playbackService.subtitles(imdb: movie.imdbCode, language: languages[requested] ?? "en")
                try Task.checkCancellation()
                subtitleCues = SubtitleParser.parse(track.text)
                guard !subtitleCues.isEmpty else { subtitleStatus = "Subtitles unavailable"; return }
                subtitleStatus = track.language == languages[requested] ? nil : "\(requested) unavailable; using English."
            } catch {
                if !Task.isCancelled { subtitleStatus = "Subtitles unavailable. Select a language to try again." }
            }
        }
    }

    private func saveProgress(flush: Bool = false) {
        guard hasConfirmedPosition, currentTime.isFinite, currentTime > 0,
              totalDuration.isFinite, totalDuration > 0 else { return }
        let position = currentTime
        if lastLocalSave.map({ abs(position - $0) >= (flush ? 0.05 : 5) }) ?? true {
            lastLocalSave = position
            DownloadStore.shared.updatePlayback(id: movie.id, position: position, duration: totalDuration)
            WatchHistorySync.saveLocal(context: modelContext, movie: movie, position: position, duration: totalDuration)
        }
        if lastCloudSave.map({ abs(position - $0) >= (flush ? 0.05 : 30) }) ?? true {
            lastCloudSave = position
            FirestoreService.shared.savePlaybackProgress(
                movieId: movie.id, title: movie.title, posterURL: movie.posterURL?.absoluteString,
                positionSeconds: position, durationSeconds: totalDuration,
                year: movie.year, genres: movie.genres ?? [], backdropURL: movie.backdropURL?.absoluteString)
        }
    }

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSec = Int(seconds)
        let mins = totalSec / 60
        let secs = totalSec % 60
        return totalSec >= 3600 ? String(format: "%d:%02d:%02d", totalSec / 3600, mins % 60, secs) : String(format: "%02d:%02d", mins, secs)
    }
}

// Wait until the fullscreen cover is attached to its scene before requesting rotation.
// Keeping this tied to the controller lifetime also preserves landscape over settings sheets.
private struct PlayerOrientationBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> OrientationController { OrientationController() }
    func updateUIViewController(_ uiViewController: OrientationController, context: Context) {}

    static func dismantleUIViewController(_ controller: OrientationController, coordinator: ()) {
        controller.restorePortrait()
    }

    final class OrientationController: UIViewController {
        private weak var scene: UIWindowScene?
        private var ownsOrientation = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !ownsOrientation, let scene = view.window?.windowScene else { return }
            self.scene = scene
            ownsOrientation = true
            MirrorAppDelegate.orientationMask = .landscape
            updateOrientationControllers(in: scene)
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                NSLog("Player landscape request failed: %@", error.localizedDescription)
            }
        }

        func restorePortrait() {
            guard ownsOrientation else { return }
            ownsOrientation = false
            MirrorAppDelegate.orientationMask = .portrait
            guard let scene else { return }
            updateOrientationControllers(in: scene)
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                NSLog("Player portrait restore failed: %@", error.localizedDescription)
            }
        }

        private func updateOrientationControllers(in scene: UIWindowScene) {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            parent?.setNeedsUpdateOfSupportedInterfaceOrientations()
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
