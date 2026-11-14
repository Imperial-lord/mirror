import Sparkle
import XCTest
@testable import MirrorDesktop

@MainActor final class DesktopUpdateTests: XCTestCase {
  private func service() -> DesktopUpdateService {
    let defaults = UserDefaults(suiteName: "UpdateTests-\(UUID().uuidString)")!
    return DesktopUpdateService(defaults: defaults, supportsInstallation: true)
  }
  func testAnAvailableUpdateDoesNotDownloadOrQuitUntilChosen() {
    let updates = service()
    var choices: [SPUUserUpdateChoice] = []
    updates.found(version: "1.2.0") { choices.append($0) }
    XCTAssertTrue(updates.hasUpdate)
    XCTAssertEqual(updates.phase, .available)
    XCTAssertTrue(choices.isEmpty)
    updates.downloadUpdate()
    updates.downloadUpdate()
    XCTAssertEqual(choices, [.install], "A double click must not start two downloads")
    XCTAssertEqual(updates.phase, .downloading)
  }
  func testProgressCancellationAndUnknownContentLength() {
    let updates = service()
    updates.found(version: "1.2.0") { _ in }
    var cancelled = false
    updates.showDownloadInitiated { cancelled = true }
    XCTAssertNil(updates.progress)
    updates.showDownloadDidReceiveExpectedContentLength(200)
    updates.showDownloadDidReceiveData(ofLength: 50)
    XCTAssertEqual(updates.progress, 0.25)
    updates.showDownloadDidReceiveData(ofLength: 300)
    XCTAssertEqual(updates.progress, 1, "An incorrect server length cannot overflow the progress UI")
    updates.cancelDownload()
    XCTAssertTrue(cancelled)
    updates.dismissUpdateInstallation()
    XCTAssertEqual(updates.phase, .available)
    XCTAssertTrue(updates.hasUpdate)
  }
  func testPreparingCannotBeCancelledAndRestartRequiresASeparateChoice() {
    let updates = service()
    var cancelled = false
    updates.showDownloadInitiated { cancelled = true }
    updates.showDownloadDidStartExtractingUpdate()
    updates.cancelDownload()
    XCTAssertFalse(cancelled)
    var installs = 0
    updates.showReady(toInstallAndRelaunch: { if $0 == .install { installs += 1 } })
    XCTAssertEqual(updates.phase, .ready)
    XCTAssertEqual(installs, 0)
    updates.restartAndInstall()
    updates.restartAndInstall()
    XCTAssertEqual(installs, 1)
  }
  func testPreferencesPersistAndSuccessfulCheckClearsHint() {
    let name = "UpdatePreferences-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let updates = DesktopUpdateService(defaults: defaults, supportsInstallation: true)
    XCTAssertTrue(updates.automaticChecks)
    updates.automaticChecks = false
    XCTAssertFalse(DesktopUpdateService(defaults: defaults, supportsInstallation: true).automaticChecks)
    updates.found(version: "1.2.0") { _ in }
    var acknowledged = false
    updates.showUpdateNotFoundWithError(NSError(domain: "test", code: 1001)) { acknowledged = true }
    XCTAssertTrue(acknowledged)
    XCTAssertFalse(updates.hasUpdate)
    XCTAssertEqual(updates.phase, .upToDate)
    XCTAssertNotNil(updates.lastChecked)
  }
  func testErrorsLeaveTheInstalledAppAloneAndReleaseLinksStayInOurRepository() {
    let updates = service()
    updates.showUpdaterError(NSError(domain: "test", code: 1)) {}
    XCTAssertEqual(updates.phase, .failed)
    updates.latestVersion = "1.2.0"
    XCTAssertEqual(updates.releaseURL?.absoluteString, "https://github.com/Imperial-lord/mirror/releases/tag/macos-v1.2.0")
    updates.latestVersion = "../../elsewhere"
    XCTAssertNil(updates.releaseURL)
  }
}
