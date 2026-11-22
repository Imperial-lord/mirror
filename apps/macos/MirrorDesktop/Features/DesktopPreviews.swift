import AVFoundation
import SwiftUI

struct DesktopPreviewSelection {
  let id: UUID
  let movieID: Int
  let title: String
  let metadata: DesktopPreviewMetadata
  let favorite: SavedMovie
  let shareURL: URL?
  let playTitle: String
  let artwork: URL?
  let clip: URL

  init(id: UUID, movie: Movie, clip: URL) {
    self.id = id
    self.movieID = movie.id
    self.title = movie.title
    self.playTitle = "Play"
    self.metadata = DesktopPreviewMetadata(
      rating: movie.rating, year: movie.year, runtime: movie.formattedRuntime,
      language: movie.language, genres: movie.genres ?? [])
    self.favorite = SavedMovie(id: movie.id, title: movie.title, year: movie.year,
      genres: movie.genres ?? [], poster: movie.posterURL?.absoluteString ?? "")
    self.shareURL = URL(string: movie.url)
    self.artwork = movie.backdropURL ?? movie.posterURL
    self.clip = clip
  }

  init(id: UUID, history: WatchHistoryItem, clip: URL) {
    self.id = id
    self.movieID = history.movieId
    self.title = history.title
    let hours = history.runtime / 60
    let minutes = history.runtime % 60
    self.metadata = DesktopPreviewMetadata(
      rating: nil, year: history.year,
      runtime: hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m",
      language: nil, genres: history.genres)
    self.favorite = SavedMovie(id: history.movieId, title: history.title, year: history.year,
      genres: history.genres, poster: history.posterURL ?? "")
    self.shareURL = nil
    self.playTitle = "Resume"
    self.artwork = (history.backdropURL ?? history.posterURL).flatMap(URL.init(string:))
    self.clip = clip
  }
}

struct DesktopPreviewMetadata {
  let rating: Double?
  let year: Int
  let runtime: String
  let language: String?
  let genres: [String]

  init(rating: Double?, year: Int, runtime: String, language: String?, genres: [String]) {
    self.rating = rating
    self.year = year
    self.runtime = runtime
    self.language = language
    self.genres = genres
  }

  init(movie: MovieDetail) {
    self.init(rating: movie.rating, year: movie.year, runtime: movie.formattedRuntime,
      language: movie.language, genres: movie.genres ?? [])
  }
}

struct DesktopClipHover: ViewModifier {
  var clip: URL?
  var selection: (UUID, URL) -> DesktopPreviewSelection
  @Environment(DesktopSession.self) private var session
  @Environment(\.scenePhase) private var scenePhase
  @State private var previewID = UUID()
  @State private var hovering = false

  func body(content: Content) -> some View {
    content
      .onHover { inside in
        hovering = inside
        if clip != nil { session.updatePreviewHover(previewID, inside: inside, overCard: false) }
      }
      .task(id: hovering && scenePhase == .active ? clip : nil) {
        guard hovering, scenePhase == .active, let clip else { return }
        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        guard session.preview?.id != previewID else { return }
        session.showPreview(selection(previewID, clip))
      }
      .anchorPreference(key: DesktopPreviewAnchor.self, value: .bounds) { anchor in
        session.preview?.id == previewID ? anchor : nil
      }
      .onChange(of: clip) { _, _ in session.closePreview(previewID) }
      .onDisappear { session.closePreview(previewID) }
  }
}

struct DesktopPreviewAnchor: PreferenceKey {
  static let defaultValue: Anchor<CGRect>? = nil
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = nextValue() ?? value
  }
}

struct DesktopPreviewLayer: View {
  var anchor: Anchor<CGRect>?
  @Environment(DesktopSession.self) private var session
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var downloadMovie: MovieDetail?
  @State private var downloadTask: Task<Void, Never>?

  var body: some View {
    GeometryReader { geometry in
      if let anchor, let selection = session.preview {
        let bounds = geometry[anchor]
        let width = min(448, max(1, geometry.size.width - 24))
        let height = min(width * 9 / 16 + 72, max(1, geometry.size.height - 24))
        let x = min(max(bounds.midX, width / 2 + 12), geometry.size.width - width / 2 - 12)
        let y = min(max(bounds.midY, height / 2 + 12), geometry.size.height - height / 2 - 12)
        DesktopPreviewCard(selection: selection) { detail in
          presentDownload(for: selection, detail: detail)
        }
          .frame(width: width, height: height)
          .id(selection.id)
          .onChange(of: bounds) { session.closePreview(selection.id) }
          .transition(cardTransition(from: bounds, x: x, y: y))
          .position(x: x, y: y)
      }
    }
    .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.32), value: session.preview?.id)
    .sheet(item: $downloadMovie) { DesktopDownloadSheet(movie: $0) }
    .onDisappear { downloadTask?.cancel() }
  }

  private func cardTransition(from bounds: CGRect, x: CGFloat, y: CGFloat) -> AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .asymmetric(
      insertion: .scale(scale: 0.84)
        .combined(with: .offset(x: bounds.midX - x, y: bounds.midY - y + 8))
        .combined(with: .opacity),
      removal: .opacity.animation(.easeOut(duration: 0.16))
    )
  }

  private func presentDownload(for selection: DesktopPreviewSelection, detail: MovieDetail?) {
    session.closePreview(selection.id)
    guard AuthService.shared.isAuthenticated else {
      session.showSignIn = true
      return
    }
    downloadTask?.cancel()
    if let detail {
      downloadMovie = detail
      return
    }
    downloadTask = Task {
      do {
        let movie = try await MovieRepository.shared.fetchMovieDetail(id: selection.movieID)
        guard !Task.isCancelled else { return }
        downloadMovie = movie
      } catch {
        if !Task.isCancelled { session.error = "Couldn’t open this movie. Please try again." }
      }
    }
  }
}

struct DesktopPreviewCard: View {
  let selection: DesktopPreviewSelection
  let download: (MovieDetail?) -> Void
  @Environment(DesktopSession.self) private var session
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("desktopPreviewAutoplay") private var autoplay = true
  @State private var showingClip = false
  @State private var clipReady = false
  @State private var detail: MovieDetail?
  @State private var savingFavorite = false
  @State private var pendingFavorite: Bool?
  private var storedFavorite: Bool {
    LibraryStore.shared.favorites.contains { $0.id == selection.movieID }
  }
  private var isFavorite: Bool {
    pendingFavorite ?? storedFavorite
  }
  private var metadata: DesktopPreviewMetadata {
    detail.map(DesktopPreviewMetadata.init) ?? selection.metadata
  }
  private var shareURL: URL? {
    let url = detail.flatMap { URL(string: $0.url) } ?? selection.shareURL
    guard let url, ["http", "https"].contains(url.scheme ?? "") else { return nil }
    return url
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DesktopImage(url: selection.artwork)
        .overlay {
          if showingClip {
            DesktopClipView(url: selection.clip) {
              clipReady = true
            } finished: {
              clipReady = false
              showingClip = false
            }
              .opacity(clipReady ? 1 : 0)
              .transition(.opacity)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .overlay {
          LinearGradient(
            stops: [.init(color: .clear, location: 0.28),
              .init(color: .black.opacity(0.32), location: 0.58),
              .init(color: .black.opacity(0.92), location: 1)],
            startPoint: .top, endPoint: .bottom
          ).allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
              if let rating = metadata.rating, rating > 0 {
                Text("IMDb \(rating, specifier: "%.1f")").fontWeight(.semibold)
              }
              if metadata.year > 0 { Text(String(metadata.year)) }
              if metadata.runtime != "0m" { Text(metadata.runtime) }
              if let language = metadata.language, !language.isEmpty {
                Text(language.uppercased())
              }
            }.font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.92))
            if !metadata.genres.isEmpty {
              Text(metadata.genres.joined(separator: " · "))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
          }.padding(.horizontal, 22).padding(.bottom, 18)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: clipReady)
        .overlay {
          Button(action: playMovie) {
            Color.clear.contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(selection.playTitle) movie from preview")
        }
      HStack(spacing: 11) {
        Button(action: playMovie) {
          actionIcon(.playBold, emphasized: true)
        }.buttonStyle(.plain)
          .help("\(selection.playTitle) movie")
          .accessibilityLabel("\(selection.playTitle) movie")
        Button(action: toggleFavorite) {
          actionIcon(isFavorite ? .check : .add)
        }.buttonStyle(.plain)
          .disabled(savingFavorite)
          .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
          .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
          .accessibilityAddTraits(isFavorite ? .isSelected : [])
        Button {
          download(detail)
        } label: {
          actionIcon(.downloadLinear)
        }.buttonStyle(.plain).help("Download movie").accessibilityLabel("Download movie")
        if let shareURL {
          ShareLink(item: shareURL) {
            actionIcon(.share)
          }.buttonStyle(.plain).help("Share movie").accessibilityLabel("Share movie")
        }
        Spacer(minLength: 14)
        Button {
          session.open(selection.movieID)
        } label: {
          Label {
            Text("Details").font(.system(size: 13, weight: .medium))
          } icon: {
            PhosphorView(.infoLinear, size: 16)
          }
          .foregroundStyle(Color.mirrorInk)
          .padding(.horizontal, 14).frame(height: 40)
          .background(Color.mirrorSurface2, in: Capsule())
          .contentShape(Capsule())
        }.buttonStyle(.plain)
      }
      .padding(.horizontal, 20).frame(height: 72)
      .background(Color.mirrorSurface1)
    }
    .background(Color.mirrorSurface1)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18).strokeBorder(Color.mirrorInk.opacity(0.1))
        .allowsHitTesting(false)
    }
    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Preview for \(selection.title)")
    .onHover { inside in
      session.updatePreviewHover(selection.id, inside: inside, overCard: true)
    }
    .onExitCommand { session.closePreview(selection.id) }
    .onChange(of: storedFavorite) { _, favorite in
      if pendingFavorite == favorite { pendingFavorite = nil }
    }
    .onChange(of: session.preview?.id) { _, id in
      if id != selection.id {
        clipReady = false
        showingClip = false
      }
    }
    .task {
      guard session.preview?.id == selection.id else { return }
      detail = try? await MovieRepository.shared.fetchMovieDetail(id: selection.movieID)
    }
    .task {
      do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
      if autoplay, !reduceMotion, session.preview?.id == selection.id {
        showingClip = true
      }
    }
  }

  private func playMovie() {
    session.play(selection.movieID)
  }

  private func actionIcon(_ icon: PhosphorIcon, emphasized: Bool = false) -> some View {
    PhosphorView(icon, size: 20, color: emphasized ? .mirrorOnInk : .mirrorInk)
      .frame(width: 42, height: 42)
      .background(emphasized ? Color.mirrorInk : .mirrorSurface2, in: Circle())
      .contentShape(Circle())
  }

  private func toggleFavorite() {
    guard !savingFavorite else { return }
    guard AuthService.shared.isAuthenticated else {
      session.closePreview(selection.id)
      session.showSignIn = true
      return
    }
    savingFavorite = true
    let shouldFavorite = !isFavorite
    pendingFavorite = shouldFavorite
    let movie = detail.map(SavedMovie.init(movie:)) ?? selection.favorite
    Task {
      defer { savingFavorite = false }
      do {
        if shouldFavorite {
          try await LibraryStore.shared.addFavorite(movie)
        } else {
          try await LibraryStore.shared.remove(movie: movie, from: nil)
        }
        if storedFavorite == shouldFavorite { pendingFavorite = nil }
      } catch {
        pendingFavorite = nil
        session.error = shouldFavorite
          ? "Couldn’t add this movie to Favorites. Please try again."
          : "Couldn’t remove this movie from Favorites. Please try again."
      }
    }
  }
}

private struct DesktopClipView: NSViewRepresentable {
  let url: URL
  let ready: () -> Void
  let finished: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspectFill
    view.wantsLayer = true
    view.layer = layer
    context.coordinator.start(player, item: item, layer: layer, ready: ready, finished: finished)
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator() }

  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.stop()
    (view.layer as? AVPlayerLayer)?.player = nil
  }

  @MainActor final class Coordinator {
    private var player: AVPlayer?
    private var observers: [NSObjectProtocol] = []
    private var firstFrame: NSKeyValueObservation?
    private var deadline: Task<Void, Never>?

    func start(
      _ player: AVPlayer, item: AVPlayerItem, layer: AVPlayerLayer,
      ready: @escaping @MainActor () -> Void, finished: @escaping () -> Void
    ) {
      self.player = player
      firstFrame = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, change in
        guard change.newValue == true else { return }
        Task { @MainActor [weak self] in
          guard let self, self.player != nil else { return }
          self.firstFrame = nil
          ready()
        }
      }
      for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
        let observer = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated {
            guard let self, self.player != nil else { return }
            self.stop()
            finished()
          }
        }
        observers.append(observer)
      }
      deadline = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(16)) } catch { return }
        self?.stop()
        finished()
      }
      player.play()
    }

    func stop() {
      deadline?.cancel()
      firstFrame = nil
      player?.pause()
      player = nil
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers = []
    }
  }
}

struct DesktopHomePreviewRequest: Equatable {
  let accountID: String?
  let movieIDs: [Int]
}
