import SwiftUI
import FirebaseAuth

public enum LaunchStep {
    case splash
    case onboarding
    case auth
    case recommendation
    case whoIsWatching
    case mainApp
}

public struct AppLaunchCoordinatorView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            switch appState.currentLaunchStep {
            case .splash:
                SplashScreenView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        if AuthService.shared.isAuthenticated {
                            appState.currentLaunchStep = .whoIsWatching
                        } else if UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
                            appState.currentLaunchStep = .auth
                        } else {
                            appState.currentLaunchStep = .onboarding
                        }
                    }
                }
                .transition(.opacity)

            case .onboarding:
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                    withAnimation(.easeInOut(duration: 0.4)) {
                        appState.currentLaunchStep = .auth
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

            case .auth:
                AuthFlowView { isNewAccount in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        if isNewAccount {
                            appState.currentLaunchStep = .recommendation
                        } else {
                            appState.currentLaunchStep = .whoIsWatching
                        }
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

            case .recommendation:
                RecommendationSetupView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        appState.currentLaunchStep = .whoIsWatching
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

            case .whoIsWatching:
                ProfileSelectionView { selectedName in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        UserDefaults.standard.set(true, forKey: "onboardingComplete")
                        UserDefaults.standard.set(selectedName, forKey: "activeProfile")
                        appState.currentLaunchStep = .mainApp
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

            case .mainApp:
                MainTabView()
                    .transition(.opacity)
            }
        }

    }
}
