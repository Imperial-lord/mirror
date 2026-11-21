import Observation
import SwiftUI
import WebKit

enum TrailerDocument {
  static func origin(bundleID: String) -> URL? {
    guard !bundleID.isEmpty, bundleID.utf8.count <= 255, bundleID.contains("."),
      bundleID.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 46
      })
    else { return nil }
    return URL(string: "https://\(bundleID)/")
  }

  static func html(_ trailer: MovieTrailer, origin: URL, token: UUID) -> String {
    var url = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(trailer.id)")!
    url.queryItems = [
      .init(name: "enablejsapi", value: "1"), .init(name: "playsinline", value: "1"),
      .init(name: "autoplay", value: "1"), .init(name: "rel", value: "0"),
      .init(name: "origin", value: String(origin.absoluteString.dropLast())),
    ]
    let source = url.url!.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
    return """
      <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
      <meta name="referrer" content="strict-origin-when-cross-origin"><title>Trailer</title>
      <style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}iframe{width:100%;height:100%;border:0;display:block}</style></head><body>
      <iframe id="player" title="Movie trailer" src="\(source)" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
      <script>
      var player;
      function notify(event,code){window.webkit.messageHandlers.trailer.postMessage({event:event,code:code||0,token:'\(token.uuidString)'});}
      function onYouTubeIframeAPIReady(){player=new YT.Player('player',{events:{
        onReady:function(){notify('ready');},
        onAutoplayBlocked:function(){notify('ready');},
        onError:function(e){notify('error',e.data);}
      }});}
      function stopTrailer(){if(player){try{player.stopVideo();player.destroy();}catch(e){}}document.querySelectorAll('iframe').forEach(function(f){f.remove();});}
      document.addEventListener('visibilitychange',function(){if(document.hidden&&player){try{player.pauseVideo();}catch(e){}}});
      </script><script src="https://www.youtube.com/iframe_api" onerror="notify('error',0)"></script></body></html>
      """
  }
}

@MainActor @Observable
final class TrailerPlayerController: NSObject, WKNavigationDelegate, WKUIDelegate {
  enum State: Equatable {
    case loading, ready
    case failed(String)
  }
  private(set) var state: State = .loading
  @ObservationIgnored let webView: WKWebView
  @ObservationIgnored private let origin: URL
  @ObservationIgnored private let document: (MovieTrailer, URL, UUID) -> String
  @ObservationIgnored private let timeout: Duration
  @ObservationIgnored private var deadline: Task<Void, Never>?
  @ObservationIgnored private(set) var token: UUID?
  @ObservationIgnored private var navigation: WKNavigation?

  init(
    origin: URL? = nil, timeout: Duration = .seconds(30),
    document: @escaping (MovieTrailer, URL, UUID) -> String = TrailerDocument.html
  ) {
    self.origin =
      origin ?? TrailerDocument.origin(
        bundleID: Bundle.main.bundleIdentifier ?? "com.imperiallord.mirror")!
    self.timeout = timeout
    self.document = document
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.preferences.isElementFullscreenEnabled = true
    #if os(iOS)
      configuration.allowsInlineMediaPlayback = true
    #endif
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.underPageBackgroundColor = .black
    super.init()
    #if os(iOS)
      webView.isOpaque = false
      webView.backgroundColor = .black
      webView.scrollView.isScrollEnabled = false
    #endif
  }

  func load(_ trailer: MovieTrailer) {
    stop()
    let id = UUID()
    token = id
    state = .loading
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.configuration.userContentController.add(TrailerMessageReceiver(self), name: "trailer")
    navigation = webView.loadHTMLString(document(trailer, origin, id), baseURL: origin)
    deadline = Task { [weak self, timeout] in
      do { try await Task.sleep(for: timeout) } catch { return }
      guard let self, self.token == id, self.state == .loading else { return }
      self.fail("The trailer couldn’t load. Check your connection and try again.")
    }
  }

  func receive(_ body: Any, mainFrame: Bool) {
    guard mainFrame, let token, let message = body as? [String: Any],
      message["token"] as? String == token.uuidString
    else { return }
    switch message["event"] as? String {
    case "ready":
      guard state == .loading else { return }
      deadline?.cancel()
      state = .ready
    case "error":
      let code = message["code"] as? Int ?? 0
      fail(
        [100, 101, 150].contains(code)
          ? "This trailer isn’t available to play inside the app."
          : "The trailer couldn’t play. Please try again.")
    default: break
    }
  }

  func pause() {
    webView.pauseAllMediaPlayback(completionHandler: nil)
  }

  func stop() {
    token = nil
    deadline?.cancel()
    deadline = nil
    navigation = nil
    pause()
    webView.stopLoading()
    webView.evaluateJavaScript("if(window.stopTrailer){stopTrailer();}", completionHandler: nil)
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "trailer")
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
  }

  private func fail(_ message: String) {
    stop()
    state = .failed(message)
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if navigation === self.navigation, (error as NSError).code != NSURLErrorCancelled {
      fail("The trailer couldn’t load. Check your connection and try again.")
    }
  }
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    self.webView(webView, didFail: navigation, withError: error)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard token != nil else { return }
    fail("The trailer stopped unexpectedly. Please try again.")
  }
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    // Keep user-initiated player links in the same in-app viewer, never launch a browser.
    if navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
    return nil
  }
}

@MainActor private final class TrailerMessageReceiver: NSObject, WKScriptMessageHandler {
  private weak var owner: TrailerPlayerController?
  init(_ owner: TrailerPlayerController) { self.owner = owner }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    owner?.receive(message.body, mainFrame: message.frameInfo.isMainFrame)
  }
}

struct TrailerPlayerView: View {
  let trailer: MovieTrailer
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var player = TrailerPlayerController()
  @State private var started = false
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(trailer.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
          Text("Official trailer").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }
        Spacer(minLength: 12)
        if player.state == .loading { ProgressView().controlSize(.small).tint(.white) }
        Button {
          player.stop()
          dismiss()
        } label: {
          PhosphorView(.close, size: 18, color: .white).frame(width: 36, height: 36)
            .background(.white.opacity(0.12), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("Close trailer")
      }.padding(20)
      GeometryReader { geometry in
        Group {
          if case .failed(let message) = player.state {
            VStack(spacing: 18) {
              Text(message).font(.system(size: 15)).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
              Button("Try again") { player.load(trailer) }
                .buttonStyle(.plain).font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 24).padding(.vertical, 12)
                .foregroundStyle(.black).background(.white, in: Capsule())
            }.padding(30)
          } else {
            TrailerWebView(player: player)
              .frame(height: max(200, min(geometry.size.height, geometry.size.width * 9 / 16)))
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.foregroundStyle(.white).background(.black).preferredColorScheme(.dark)
      // Native YouTube fullscreen can temporarily cover this view; don't restart on return.
      .onAppear {
        guard !started else { return }
        started = true
        player.load(trailer)
      }
      .onChange(of: scenePhase) { _, phase in if phase != .active { player.pause() } }
      #if os(iOS)
        .background(PlayerOrientationBridge())
      #endif
  }
}

#if os(iOS)
  private struct TrailerWebView: UIViewRepresentable {
    let player: TrailerPlayerController
    func makeCoordinator() -> TrailerPlayerController { player }
    func makeUIView(context: Context) -> WKWebView { player.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: TrailerPlayerController) {
      coordinator.stop()
    }
  }
#else
  private struct TrailerWebView: NSViewRepresentable {
    let player: TrailerPlayerController
    func makeCoordinator() -> TrailerPlayerController { player }
    func makeNSView(context: Context) -> WKWebView { player.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    static func dismantleNSView(_ nsView: WKWebView, coordinator: TrailerPlayerController) {
      coordinator.stop()
    }
  }
#endif
