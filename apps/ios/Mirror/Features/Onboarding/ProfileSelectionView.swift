import SwiftUI

public struct ProfileSelectionView: View {
    public var onProfileSelected: (String) -> Void
    @State private var authService = AuthService.shared
    @State private var isShowingAddProfile = false
    @State private var isManagingProfiles = false
    @State private var signOutError: String?
    @Environment(AppState.self) private var appState

    public init(onProfileSelected: @escaping (String) -> Void) {
        self.onProfileSelected = onProfileSelected
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Edit profile") { isManagingProfiles = true }
                            .font(.system(size: 13)).foregroundStyle(Color.mirrorTextSecondary)
                            .disabled(authService.profiles.isEmpty)
                    }
                    .frame(height: 44)
                    Spacer(minLength: 40)
                    Text("Who's watching?").font(.system(size: 24, weight: .medium))
                        .padding(.bottom, 36)
                    if authService.isLoadingProfiles && authService.profiles.isEmpty {
                        ProgressView("Loading profiles…")
                    } else if let error = authService.profileError {
                        VStack(spacing: 16) {
                            Text(error).font(.system(size: 13)).foregroundStyle(Color.mirrorTextSecondary)
                            Button("Try again") {
                                Task { if let user = authService.currentUser { await authService.loadProfiles(for: user.uid) } }
                            }
                            Button("Sign out") {
                                do { try appState.signOut() }
                                catch { signOutError = error.localizedDescription }
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)], spacing: 28) {
                            ForEach(authService.profiles) { profile in
                                Button {
                                    authService.selectProfile(profile)
                                    onProfileSelected(profile.name)
                                } label: {
                                    VStack(spacing: 10) {
                                        ProfileAvatarView(profile: profile, size: 88)
                                            .overlay(Circle().strokeBorder(authService.currentProfile?.id == profile.id ? Color.mirrorTextSecondary : .clear, lineWidth: 1))
                                        Text(profile.name).font(.system(size: 14)).lineLimit(2)
                                        if profile.isKid {
                                            Text("KID").font(.system(size: 10)).foregroundStyle(Color.mirrorTextTertiary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .accessibilityLabel("Watch as \(profile.name)")
                            }
                        }
                        .frame(maxWidth: 280)
                        Button { isShowingAddProfile = true } label: {
                            VStack(spacing: 10) {
                                PhosphorView(.add, size: 24)
                                    .frame(width: 72, height: 72)
                                    .background(Color.mirrorSurface1, in: Circle())
                                Text("Add Profile").font(.system(size: 12))
                            }
                            .foregroundStyle(Color.mirrorTextTertiary)
                        }
                        .padding(.top, 32)
                    }
                    Spacer(minLength: 80)
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Color.mirrorBackground.ignoresSafeArea())
        .tint(.mirrorAccent)

        .task {
            if authService.profiles.isEmpty, let user = authService.currentUser {
                await authService.loadProfiles(for: user.uid)
            }
        }
        .fullScreenCover(isPresented: $isShowingAddProfile) { ProfileEditorView() }
        .fullScreenCover(isPresented: $isManagingProfiles) { ManageProfilesView() }
        .alert("Unable to sign out", isPresented: Binding(get: { signOutError != nil }, set: { if !$0 { signOutError = nil } })) {
            Button("OK") { signOutError = nil }
        } message: { Text(signOutError ?? "") }
    }
}
