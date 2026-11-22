import AVFoundation
import NukeUI
import SwiftUI

struct MovieDetailHero: View {
    let movie: MovieDetail
    let isObscured: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previewURL: URL?
    @State private var autoplayAt: ContinuousClock.Instant?
    @State private var hasPlayed = false
    @State private var playbackID: UUID?
    @State private var isVideoVisible = false

    private var accountID: String? { AuthService.shared.currentUser?.uid }
    private var canPlayPreview: Bool { scenePhase == .active && !isObscured }
    private var autoplayURL: URL? { canPlayPreview && autoplayAt != nil ? previewURL : nil }
    private var previewFade: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.3) }

    var body: some View {
        ZStack(alignment: .top) {
            // Background Poster / Backdrop
            ZStack(alignment: .bottom) {
                if let poster = movie.posterURL ?? movie.backdropURL {
                    LazyImage(url: poster) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color(mirrorHex: "1C1C1C")
                        }
                    }
                    .onCompletion { _ in scheduleAutoplay() }
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .clipped()
                } else {
                    Color(mirrorHex: "1C1C1C")
                        .frame(maxWidth: .infinity)
                        .frame(height: 420)
                        .onAppear(perform: scheduleAutoplay)
                }

                // Keep the poster below the video so loading and failures never expose a blank frame.
                if let playbackID, let previewURL {
                    MoviePreviewPlayer(url: previewURL) {
                        guard self.playbackID == playbackID else { return }
                        withAnimation(previewFade) { isVideoVisible = true }
                    } finished: {
                        finishPreview(playbackID)
                    }
                    .id(playbackID)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .opacity(isVideoVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                // Dark Gradient Fade into Background
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color(mirrorHex: "060606").opacity(0.3),
                        Color(mirrorHex: "060606").opacity(0.8),
                        Color(mirrorHex: "060606")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }

            LinearGradient(colors: [Color(mirrorHex: "000000").opacity(scheme == .dark ? 0.55 : 0.86), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .allowsHitTesting(false)

            // Top Navigation Bar: Back Button & Rating Badges
            HStack {
                Button(action: { dismiss() }) {
                    PhosphorView(.caretLeft, size: 18)
                        .foregroundStyle(Color.mirrorInk)
                        .frame(width: 40, height: 40)
                        .background(Color(mirrorHex: "121215").opacity(0.65))
                        .clipShape(Circle())
                }

                Spacer()

                HStack(spacing: 8) {
                    if previewURL != nil {
                        Button(action: playPreview) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.mirrorInk)
                                .frame(width: 28, height: 28)
                                .background(Color(mirrorHex: "121215").opacity(0.75), in: Circle())
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Replay preview")
                        .disabled(playbackID != nil || !canPlayPreview)
                        .padding(.trailing, -8)
                    }

                    // IMDb Rating Pill (Translucent)
                    HStack(spacing: 3) {
                        Text("IMDb")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(Color.mirrorInk)
                        Text(String(format: "%.1f", movie.rating))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.mirrorInk)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(mirrorHex: "121215").opacity(0.75))
                    .overlay(Capsule().stroke(Color.mirrorInk.opacity(0.15), lineWidth: 1))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 62)
        }
        .task(id: accountID) {
            guard accountID != nil else { return }
            let clip = try? await PlaybackService.homePreview(movieID: movie.id)
            guard !Task.isCancelled else { return }
            previewURL = clip
        }
        .task(id: autoplayURL) {
            guard autoplayURL != nil, let autoplayAt, !hasPlayed else { return }
            do { try await ContinuousClock().sleep(until: autoplayAt) } catch { return }
            guard !Task.isCancelled, !hasPlayed else { return }
            playPreview()
        }
        .onChange(of: accountID) {
            stopPreview()
            previewURL = nil
        }
        .onChange(of: canPlayPreview) {
            if !canPlayPreview { stopPreview() }
        }
        .onDisappear(perform: stopPreview)
    }

    private func scheduleAutoplay() {
        if autoplayAt == nil {
            autoplayAt = ContinuousClock.now.advanced(by: .seconds(1))
        }
    }

    private func playPreview() {
        guard canPlayPreview, previewURL != nil, playbackID == nil else { return }
        hasPlayed = true
        playbackID = UUID()
    }

    private func finishPreview(_ id: UUID) {
        guard playbackID == id else { return }
        withAnimation(previewFade) {
            isVideoVisible = false
        } completion: {
            if playbackID == id { playbackID = nil }
        }
    }

    private func stopPreview() {
        isVideoVisible = false
        playbackID = nil
    }
}

private struct MoviePreviewPlayer: UIViewRepresentable {
    let url: URL
    let ready: @MainActor () -> Void
    let finished: @MainActor () -> Void

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        context.coordinator.start(url: url, layer: view.playerLayer, ready: ready, finished: finished)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    @MainActor final class Coordinator {
        private var player: AVPlayer?
        private var firstFrame: NSKeyValueObservation?
        private var itemStatus: NSKeyValueObservation?
        private var endObservers: [NSObjectProtocol] = []
        private var deadline: Task<Void, Never>?

        func start(
            url: URL, layer: AVPlayerLayer,
            ready: @escaping @MainActor () -> Void, finished: @escaping @MainActor () -> Void
        ) {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            self.player = player
            layer.videoGravity = .resizeAspectFill
            layer.player = player

            firstFrame = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, change in
                guard change.newValue == true else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.firstFrame != nil else { return }
                    self.firstFrame = nil
                    self.setDeadline(.seconds(10), finished: finished)
                    ready()
                }
            }
            itemStatus = item.observe(\.status, options: [.initial, .new]) { [weak self] _, change in
                guard change.newValue == .failed else { return }
                Task { @MainActor [weak self] in self?.finish(finished) }
            }
            for name in [
                AVPlayerItem.didPlayToEndTimeNotification,
                AVPlayerItem.failedToPlayToEndTimeNotification
            ] {
                endObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: item, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finish(finished) }
                })
            }
            setDeadline(.seconds(8), finished: finished)
            player.play()
        }

        private func setDeadline(_ delay: Duration, finished: @escaping @MainActor () -> Void) {
            deadline?.cancel()
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: delay) } catch { return }
                self?.finish(finished)
            }
        }

        private func finish(_ finished: @MainActor () -> Void) {
            guard player != nil else { return }
            stop()
            finished()
        }

        func stop() {
            deadline?.cancel()
            firstFrame = nil
            itemStatus = nil
            player?.pause()
            player = nil
            for observer in endObservers { NotificationCenter.default.removeObserver(observer) }
            endObservers.removeAll()
        }
    }
}
