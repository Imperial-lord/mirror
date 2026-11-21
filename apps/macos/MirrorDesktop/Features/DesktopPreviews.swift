import AVFoundation
import FirebaseAuth
import SwiftUI

struct DesktopPreviewSelection {
  let id: UUID
  let movieID: Int
  let title: String
  let subtitle: String
  let artwork: URL?
  let clip: URL

  init(id: UUID, movie: Movie, clip: URL) {
    self.id = id
    self.movieID = movie.id
    self.title = movie.title
    self.subtitle = ([String(movie.year)] + (movie.runtime > 0 ? [movie.formattedRuntime] : [])
      + Array((movie.genres ?? []).prefix(2))).joined(separator: " · ")
    self.artwork = movie.backdropURL ?? movie.posterURL
    self.clip = clip
  }

  init(id: UUID, history: WatchHistoryItem, clip: URL) {
    self.id = id
    self.movieID = history.movieId
    self.title = history.title
    self.subtitle = history.subtitle
    self.artwork = (history.backdropURL ?? history.posterURL).flatMap(URL.init(string:))
    self.clip = clip
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
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
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

  var body: some View {
    GeometryReader { geometry in
      if let anchor, let selection = session.preview {
        let bounds = geometry[anchor]
        let width: CGFloat = 368
        let height: CGFloat = 326
        let x = min(max(bounds.midX, width / 2 + 12), geometry.size.width - width / 2 - 12)
        let y = min(max(bounds.midY, height / 2 + 12), geometry.size.height - height / 2 - 12)
        DesktopPreviewCard(selection: selection)
          .frame(width: width, height: height)
          .position(x: x, y: y)
          .id(selection.id)
          .onChange(of: bounds) { session.closePreview(selection.id) }
          .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.22), value: session.preview?.id)
  }
}

private struct DesktopPreviewCard: View {
  let selection: DesktopPreviewSelection
  @Environment(DesktopSession.self) private var session
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("desktopPreviewAutoplay") private var autoplay = true
  @State private var showingClip = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DesktopImage(url: selection.artwork)
        .frame(height: 207)
        .overlay {
          if showingClip {
            DesktopClipView(url: selection.clip) { showingClip = false }
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .clipped()
      VStack(alignment: .leading, spacing: 9) {
        Text(selection.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
        if !selection.subtitle.isEmpty {
          Text(selection.subtitle).font(.caption).foregroundStyle(Color.mirrorTextSecondary).lineLimit(1)
        }
        HStack(spacing: 12) {
          DesktopAction(title: "Play", icon: .playBold, primary: true) {
            session.closePreview(selection.id)
            session.play(selection.movieID)
          }
          Spacer(minLength: 0)
          Button {
            session.open(selection.movieID)
          } label: {
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
              .frame(width: 36, height: 36).background(Color.mirrorSurface2, in: Circle())
          }.buttonStyle(.plain).help("More details").accessibilityLabel("More details")
        }
      }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .background(Color.mirrorSurface1)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18).strokeBorder(Color.mirrorInk.opacity(0.1))
        .allowsHitTesting(false)
    }
    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    .contentShape(Rectangle())
    .onHover { inside in
      session.updatePreviewHover(selection.id, inside: inside, overCard: true)
    }
    .onExitCommand { session.closePreview(selection.id) }
    .onChange(of: session.preview?.id) { _, id in
      if id != selection.id { showingClip = false }
    }
    .task {
      do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
      if autoplay, !reduceMotion, session.preview?.id == selection.id {
        showingClip = true
      }
    }
  }
}

private struct DesktopClipView: NSViewRepresentable {
  let url: URL
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
    context.coordinator.start(player, item: item, finished: finished)
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
    private var deadline: Task<Void, Never>?

    func start(_ player: AVPlayer, item: AVPlayerItem, finished: @escaping () -> Void) {
      self.player = player
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

  static func refresh(_ ids: [Int]) async throws -> [Int: URL] {
    let configured = UserDefaults.standard.string(forKey: "PlaybackServiceURL")
      ?? Bundle.main.object(forInfoDictionaryKey: "PlaybackServiceURL") as? String
    guard let configured, let base = URL(string: configured),
      base.scheme == "https", let user = Auth.auth().currentUser
    else { return [:] }
    var request = URLRequest(url: base.appendingPathComponent("v1/home-previews"))
    request.httpMethod = "POST"
    request.timeoutInterval = 8
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(Array(ids.prefix(320)))
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 512 * 1024
    else { throw URLError(.badServerResponse) }
    let clips = try JSONDecoder().decode([Int: URL].self, from: data)
    let wanted = Set(ids)
    return clips.filter { id, url in
      guard let host = url.host, url.scheme == "https", wanted.contains(id) else { return false }
      return host.hasPrefix("objectstorage.") && host.hasSuffix(".oraclecloud.com")
    }
  }
}
