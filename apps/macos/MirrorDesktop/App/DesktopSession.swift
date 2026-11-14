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
  private var openingTask: Task<Void, Never>?
  func navigate(_ section: DesktopSection) {
    openingTask?.cancel()
    playback = nil
    self.section = section
    path = NavigationPath()
  }
  func open(_ id: Int) {
    openingTask?.cancel()
    path.append(DesktopRoute.movie(id))
  }
  func play(_ id: Int) {
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
