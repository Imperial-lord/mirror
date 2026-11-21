import SwiftData
import SwiftUI

enum DesktopSection: String, CaseIterable, Identifiable {
  case home = "Home"
  case catalog = "Catalog"
  case library = "Library"
  case downloads = "Downloads"
  case account = "Account"
  case settings = "Settings"
  var id: String { rawValue }
  var icon: PhosphorIcon {
    switch self {
    case .home: return .homeLinear
    case .catalog: return .searchLinear
    case .library: return .bookmarkLinear
    case .downloads: return .downloadLinear
    case .account: return .profileLinear
    case .settings: return .settingLinear
    }
  }
}
enum DesktopRoute: Hashable {
  case movie(Int)
  case person(Cast)
  case collection(String, [Int])
  case history(HistoryCollection)
}
struct DesktopPlayback: Identifiable {
  let id = UUID()
  let movie: MovieDetail
  var offline: OfflineMovie? = nil
}
@MainActor @Observable final class DesktopSession {
  var section: DesktopSection = .home
  var path = NavigationPath()
  var playback: DesktopPlayback?
  var browsing = false
  var showSignIn = false
  var showProfiles = false
  var error: String?
  var preview: DesktopPreviewSelection?
  private var previewCloseTask: Task<Void, Never>?
  private var previewSourceInside = false
  private var previewCardInside = false
  func showPreview(_ selection: DesktopPreviewSelection) {
    guard playback == nil, !showSignIn, !showProfiles else { return }
    previewCloseTask?.cancel()
    previewSourceInside = true
    previewCardInside = false
    preview = selection
  }
  func updatePreviewHover(_ id: UUID, inside: Bool, overCard: Bool) {
    guard preview?.id == id else { return }
    if overCard { previewCardInside = inside } else { previewSourceInside = inside }
    previewCloseTask?.cancel()
    guard !previewSourceInside, !previewCardInside else { return }
    previewCloseTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
      self?.closePreview(id)
    }
  }
  func closePreview(_ id: UUID? = nil) {
    guard id == nil || preview?.id == id else { return }
    previewCloseTask?.cancel()
    previewCloseTask = nil
    previewSourceInside = false
    previewCardInside = false
    preview = nil
  }
  private var openingTask: Task<Void, Never>?
  func navigate(_ section: DesktopSection) {
    closePreview()
    openingTask?.cancel()
    playback = nil
    self.section = section
    path = NavigationPath()
  }
  func open(_ id: Int) {
    closePreview()
    openingTask?.cancel()
    path.append(DesktopRoute.movie(id))
  }
  func goBack() {
    closePreview()
    openingTask?.cancel()
    guard !path.isEmpty else { return }
    path.removeLast()
  }
  func play(_ id: Int) {
    closePreview()
    guard AuthService.shared.isAuthenticated else {
      showSignIn = true
      return
    }
    openingTask?.cancel()
    openingTask = Task {
      do {
        let movie = try await MovieRepository.shared.fetchMovieDetail(id: id)
        guard !Task.isCancelled else { return }
        playback = DesktopPlayback(movie: movie)
      } catch {
        if !Task.isCancelled { self.error = "Couldn’t open this movie. Please try again." }
      }
    }
  }
}

extension Notification.Name {
  static let mirrorFocusSearch = Notification.Name("mirrorFocusSearch")
  static let mirrorPlayPause = Notification.Name("mirrorPlayPause")
  static let mirrorSkipForward = Notification.Name("mirrorSkipForward")
  static let mirrorSkipBackward = Notification.Name("mirrorSkipBackward")
  static let mirrorFullscreen = Notification.Name("mirrorFullscreen")
}
