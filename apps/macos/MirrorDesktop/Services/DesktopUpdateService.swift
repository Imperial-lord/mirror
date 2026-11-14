import AppKit
import Sparkle
import SwiftUI

enum DesktopUpdatePhase {
  case idle, checking, available, downloading, preparing, ready, installing, upToDate, failed
}

/// Sparkle owns verification, extraction, replacement and relaunch. This driver
/// only presents those states in Mirror's Settings, without interrupting a movie.
@MainActor @Observable final class DesktopUpdateService: NSObject, SPUUserDriver, SPUUpdaterDelegate {
  static let shared = DesktopUpdateService()
  var phase: DesktopUpdatePhase = .idle
  var latestVersion: String?
  var message: String?
  var downloaded: UInt64 = 0
  var total: UInt64 = 0
  var extractionProgress: Double = 0
  var lastChecked: Date?
  var automaticChecks: Bool {
    didSet {
      defaults.set(automaticChecks, forKey: "mirrorAutomaticUpdateChecks")
      updater?.automaticallyChecksForUpdates = automaticChecks
    }
  }
  let supportsInstallation: Bool
  let currentVersion: String
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let bundle: Bundle
  @ObservationIgnored private var updater: SPUUpdater?
  @ObservationIgnored private var updateReply: ((SPUUserUpdateChoice) -> Void)?
  @ObservationIgnored private var installReply: ((SPUUserUpdateChoice) -> Void)?
  @ObservationIgnored private var cancellation: (() -> Void)?
  @ObservationIgnored private var cancelled = false
  @ObservationIgnored private var installOnFind = false

  init(bundle: Bundle = .main, defaults: UserDefaults = .standard, supportsInstallation: Bool? = nil) {
    self.bundle = bundle
    self.defaults = defaults
    self.supportsInstallation = supportsInstallation
      ?? ((bundle.object(forInfoDictionaryKey: "MirrorPortableBuild") as? String) == "YES")
    currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    automaticChecks = defaults.object(forKey: "mirrorAutomaticUpdateChecks") as? Bool ?? true
    lastChecked = defaults.object(forKey: "mirrorLastUpdateCheck") as? Date
    super.init()
  }
  var hasUpdate: Bool { latestVersion != nil && phase != .upToDate }
  var busy: Bool { [.checking, .downloading, .preparing, .installing].contains(phase) }
  var progress: Double? {
    guard phase == .downloading, total > 0 else { return nil }
    return min(1, Double(downloaded) / Double(total))
  }
  var status: String {
    switch phase {
    case .idle: return supportsInstallation ? "Ready to check for updates" : "Development build"
    case .checking: return "Checking for updates…"
    case .available: return "Mirror \(latestVersion ?? "") is available"
    case .downloading: return "Downloading update…"
    case .preparing: return "Preparing update…"
    case .ready: return "Ready to restart"
    case .installing: return "Restarting Mirror…"
    case .upToDate: return "You’re up to date"
    case .failed: return "Couldn’t complete the update"
    }
  }
  var releaseURL: URL? {
    guard let latestVersion, latestVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { return nil }
    return URL(string: "https://github.com/Imperial-lord/mirror/releases/tag/macos-v\(latestVersion)")
  }
  func start() {
    guard supportsInstallation, updater == nil else { return }
    let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)
    self.updater = updater
    do {
      try updater.start()
      updater.automaticallyDownloadsUpdates = false
      updater.automaticallyChecksForUpdates = automaticChecks
      if automaticChecks { updater.checkForUpdatesInBackground() }
    } catch {
      phase = .failed
      message = "Updates couldn’t start. Please check again or download Mirror from GitHub."
    }
  }
  func checkNow() {
    guard supportsInstallation, !busy, let updater, updater.canCheckForUpdates else { return }
    message = nil
    cancelled = false
    updater.checkForUpdates()
  }
  func downloadUpdate() {
    guard supportsInstallation, !busy else { return }
    message = nil
    cancelled = false
    if let reply = updateReply {
      updateReply = nil
      phase = .downloading
      reply(.install)
    } else if let updater, updater.canCheckForUpdates {
      installOnFind = true
      updater.checkForUpdates()
    }
  }
  func restartAndInstall() {
    guard phase == .ready, let reply = installReply else { return }
    installReply = nil
    phase = .installing
    reply(.install)
  }
  func cancelDownload() {
    guard phase == .downloading || phase == .checking, let cancellation else { return }
    self.cancellation = nil
    cancelled = true
    phase = hasUpdate ? .available : .idle
    cancellation()
  }
  private func checked() {
    lastChecked = Date()
    defaults.set(lastChecked, forKey: "mirrorLastUpdateCheck")
  }
  // Kept separate from Sparkle's opaque state for deterministic UI/lifecycle tests.
  func found(version: String, reply: @escaping (SPUUserUpdateChoice) -> Void) {
    checked()
    latestVersion = version
    message = nil
    phase = .available
    updateReply = reply
    if installOnFind {
      installOnFind = false
      downloadUpdate()
    }
  }
  func show(_ request: SPUUpdatePermissionRequest,
                                   reply: @escaping (SUUpdatePermissionResponse) -> Void) {
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks, sendSystemProfile: false))
  }
  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    self.cancellation = cancellation
    phase = .checking
  }
  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                       reply: @escaping (SPUUserUpdateChoice) -> Void) {
    if appcastItem.isInformationOnlyUpdate {
      reply(.dismiss)
      phase = .failed
      message = "This release needs a manual download from GitHub."
      return
    }
    if state.stage == .installing {
      checked()
      latestVersion = appcastItem.displayVersionString
      installReply = reply
      phase = .ready
      return
    }
    found(version: appcastItem.displayVersionString, reply: reply)
  }
  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    checked()
    latestVersion = nil
    installOnFind = false
    message = nil
    phase = .upToDate
    acknowledgement()
  }
  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    if !cancelled {
      phase = .failed
      message = "Please try again. Your current app and saved movies are safe."
    }
    acknowledgement()
  }
  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    self.cancellation = cancellation
    downloaded = 0
    total = 0
    phase = .downloading
  }
  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    total = expectedContentLength
  }
  func showDownloadDidReceiveData(ofLength length: UInt64) { downloaded += length }
  func showDownloadDidStartExtractingUpdate() {
    cancellation = nil
    extractionProgress = 0
    phase = .preparing
  }
  func showExtractionReceivedProgress(_ progress: Double) { extractionProgress = min(1, max(0, progress)) }
  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    installReply = reply
    phase = .ready
  }
  func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                            retryTerminatingApplication: @escaping () -> Void) {
    phase = .installing
  }
  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    latestVersion = nil
    phase = .upToDate
    acknowledgement()
  }
  func dismissUpdateInstallation() {
    updateReply = nil
    installReply = nil
    cancellation = nil
    installOnFind = false
    if cancelled { phase = latestVersion == nil ? .idle : .available }
  }
  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    checked()
    if let error = error as NSError?, error.code != Int(SUError.noUpdateError.rawValue), !cancelled, phase != .failed {
      phase = .failed
      message = "Unable to check GitHub right now. Please try again later."
    } else if phase == .checking || phase == .idle {
      phase = .upToDate
    }
  }
}
