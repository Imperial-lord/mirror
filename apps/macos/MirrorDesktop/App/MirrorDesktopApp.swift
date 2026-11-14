import AppKit
import FirebaseCore
import GoogleSignIn
import Nuke
import SwiftData
import SwiftUI

@main
struct MirrorDesktopApp: App {
  @NSApplicationDelegateAdaptor(DesktopAppDelegate.self) private var delegate
  @State private var session = DesktopSession()
  @AppStorage("mirrorTheme") private var theme = DesktopTheme.dark.rawValue
  private static var isTesting: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
  }
  init() {
    if Self.isTesting {
      let options = FirebaseOptions(
        googleAppID: "1:123456789:ios:1234567890abcdef", gcmSenderID: "123456789")
      options.apiKey = "emulator-api-key"
      options.projectID = "demo-mirror-auth"
      FirebaseApp.configure(options: options)
    } else {
      FirebaseApp.configure()
    }
    var configuration = ImagePipeline.Configuration()
    configuration.isProgressiveDecodingEnabled = false
    configuration.dataCache = try? DataCache(name: "com.mirror.desktop.images")
    ImagePipeline.shared = ImagePipeline(configuration: configuration)
  }
  var body: some Scene {
    WindowGroup("Mirror", id: "mirror") {
      Group {
        if Self.isTesting { Color.mirrorBackground } else { DesktopRootView().environment(session) }
      }
      .preferredColorScheme((DesktopTheme(rawValue: theme) ?? .dark).scheme)
      .frame(minWidth: 980, minHeight: 680)
      .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
    }
    .defaultSize(width: 1380, height: 900)
    .windowStyle(.hiddenTitleBar)
    .modelContainer(
      for: [WatchHistoryItem.self, WatchlistItem.self, DownloadItem.self], inMemory: Self.isTesting
    )
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { session.navigate(.settings) }.keyboardShortcut(",")
      }
      CommandMenu("Navigate") {
        Button("Home") { session.navigate(.home) }.keyboardShortcut("1")
        Button("Catalog") { session.navigate(.catalog) }.keyboardShortcut("2")
        Button("Library") { session.navigate(.library) }.keyboardShortcut("3")
        Button("Downloads") { session.navigate(.downloads) }.keyboardShortcut("4")
        Button("Search Movies") {
          session.navigate(.catalog)
          NotificationCenter.default.post(name: .mirrorFocusSearch, object: nil)
        }.keyboardShortcut("f")
      }
      CommandMenu("Playback") {
        Button("Play / Pause") { post(.mirrorPlayPause) }.keyboardShortcut(.space, modifiers: [])
          .disabled(session.playback == nil)
        Button("Forward 10 seconds") { post(.mirrorSkipForward) }.keyboardShortcut(
          .rightArrow, modifiers: []
        ).disabled(session.playback == nil)
        Button("Back 10 seconds") { post(.mirrorSkipBackward) }.keyboardShortcut(
          .leftArrow, modifiers: []
        ).disabled(session.playback == nil)
        Divider()
        Button("Enter / Exit Full Screen") { post(.mirrorFullscreen) }.keyboardShortcut(
          "f", modifiers: []
        ).disabled(session.playback == nil)
      }
    }
  }
  private func post(_ name: Notification.Name) {
    NotificationCenter.default.post(name: name, object: nil)
  }
}
final class DesktopAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
