import SwiftUI
import UIKit
import SwiftData
import Nuke
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@MainActor
@Observable
public final class AppState {
    public var currentLaunchStep: LaunchStep
    public var currentRoute: Route?

    public init() {
        self.currentLaunchStep = .splash
        #if DEBUG
        if CommandLine.arguments.contains("--auth-preview") { self.currentLaunchStep = .auth }
        #endif
        self.currentRoute = nil
    }

    public var isAuthenticated: Bool {
        AuthService.shared.isAuthenticated
    }

    public func signOut() throws {
        try AuthService.shared.signOut()
        withAnimation(.easeInOut(duration: 0.35)) {
            self.currentLaunchStep = .auth
        }
    }
}

@main
struct MirrorApp: App {
    @UIApplicationDelegateAdaptor(MirrorAppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @AppStorage("appThemeMode") private var themeMode = AppThemeMode.dark.rawValue

    init() {
        FirebaseApp.configure()
        configureNuke()
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchCoordinatorView()
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task { DownloadStore.shared.start() }
                .environment(appState)
                .preferredColorScheme((AppThemeMode(rawValue: themeMode) ?? .dark).colorScheme)

        }
        .modelContainer(for: [
            WatchlistItem.self,
            DownloadItem.self,
            WatchHistoryItem.self
        ])
    }

    private func configureNuke() {
        var configuration = ImagePipeline.Configuration()
        // Failed requests can retain their last partial preview in LazyImage.
        // Only display completed images so interrupted downloads cannot leave
        // a half-decoded poster visible indefinitely.
        configuration.isProgressiveDecodingEnabled = false
        if let dataCache = try? DataCache(name: "com.mirror.images") {
            configuration.dataCache = dataCache
        }
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }
}

/// Browsing stays in portrait; the fullscreen player temporarily permits landscape.
@MainActor
final class MirrorAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        DownloadStore.shared.backgroundEvents(identifier: identifier, completion: completionHandler)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}
