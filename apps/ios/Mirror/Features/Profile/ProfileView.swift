import SwiftUI

public struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var authService = AuthService.shared

    @State private var isShowingSettings = false
    @State private var isShowingSubscriptions = false
    @State private var isShowingDevices = false
    @State private var isShowingManageProfiles = false
    @State private var signOutError: String?
    @State private var isShowingAboutService = false
    @State private var isShowingCreateProfile = false
    @State private var isShowingSignOutAlert = false
    @State private var editingProfile: MirrorUserProfile? = nil


    public init() {}

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var profilesList: [MirrorUserProfile] { authService.profiles }

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Account")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.mirrorInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .padding(.top, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        if let error = authService.profileError {
                            VStack(spacing: 12) {
                                Text(error).font(.subheadline).foregroundStyle(.secondary)
                                Button("Try again") {
                                    Task { if let user = authService.currentUser { await authService.loadProfiles(for: user.uid) } }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        }
                        // Profile Header Card (Behance Board 18 / Board 09)
                        VStack(spacing: 16) {
                            // Horizontal scrolling profile avatar switcher (prevents any layout stretch)
                            GeometryReader { geometry in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 18) {
                                    ForEach(profilesList) { prof in
                                        let isSelected = authService.currentProfile?.id == prof.id || (authService.currentProfile == nil && prof.id == profilesList.first?.id)
                                        Button(action: {
                                            HapticManager.shared.selection()
                                            authService.selectProfile(prof)
                                        }) {
                                            VStack(spacing: 6) {
                                                ProfileAvatarView(profile: prof)
                                                    .overlay(Circle().strokeBorder(isSelected ? Color.mirrorInk : .clear, lineWidth: 2))
                                                    .padding(3)
                                                Text(prof.name)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(isSelected ? Color.mirrorInk : Color.mirrorTextTertiary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 80)
                                        }
                                    }

                                    // Add Profile Button
                                    Button(action: {
                                        HapticManager.shared.selection()
                                        isShowingCreateProfile = true
                                    }) {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .stroke(Color.mirrorInk.opacity(0.2), lineWidth: 1)
                                                    .frame(width: 58, height: 58)
                                                    .padding(3)
                                                PhosphorView(.add, size: 20, color: Color.mirrorInk)
                                            }

                                            Text("Add profile")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(Color.mirrorTextTertiary)
                                        }
                                        .frame(width: 80)
                                    }
                                }
                                .padding(.horizontal, 3)
                                .padding(.vertical, 4)
                                .frame(minWidth: geometry.size.width, alignment: .center)
                            }
                            }
                            .frame(height: 100)

                            // Manage Profiles Link (Opens Edit Profile)
                            Button(action: {
                                HapticManager.shared.selection()
                                isShowingManageProfiles = true
                            }) {
                                HStack(spacing: 6) {
                                    PhosphorView(.editLinear, size: 14, color: Color.mirrorTextSecondary)
                                    Text("Manage profiles")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(Color.mirrorTextSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, Spacing.md)

                        // 6 Action Cards Grid (Exact Behance Board 09 / Board 18 layout)
                        LazyVGrid(columns: columns, spacing: 14) {
                            accountMenuCard(title: "Settings", icon: .settingLinear) {
                                isShowingSettings = true
                            }

                            accountMenuCard(title: "Account", icon: .profileLinear) {
                                editingProfile = authService.currentProfile ?? profilesList.first
                            }

                            accountMenuCard(title: "Subscriptions", icon: .ticketLinear) {
                                isShowingSubscriptions = true
                            }

                            accountMenuCard(title: "Support", icon: .headphoneLinear) {
                                // Support info
                            }

                            accountMenuCard(title: "About service", icon: .infoLinear) {
                                isShowingAboutService = true
                            }

                            accountMenuCard(title: "Devices", icon: .monitorLinear) {
                                isShowingDevices = true
                            }
                        }
                        .padding(.horizontal, Spacing.md)

                        Spacer().frame(height: 10)

                        // Sign Out Button (Behance Board 18)
                        Button(action: {
                            HapticManager.shared.notification(.warning)
                            isShowingSignOutAlert = true
                        }) {
                            HStack(spacing: 8) {
                                PhosphorView(.logoutLinear, size: 18, color: Color(mirrorHex: "EF4444"))
                                Text("Sign Out")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(Color(mirrorHex: "EF4444"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, Spacing.md)
                        }
                        if let email = authService.currentUser?.email {
                            Text(email).font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
                        }
                    }
                    .padding(.bottom, 110) // Clearance for floating tab bar
                }
            }
            .frame(maxWidth: .infinity)
        }
        .tint(.mirrorAccent)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Unable to sign out", isPresented: Binding(get: { signOutError != nil }, set: { if !$0 { signOutError = nil } })) {
            Button("OK") { signOutError = nil }
        } message: { Text(signOutError ?? "") }
        .task {
            if let user = authService.currentUser {
                await authService.loadProfiles(for: user.uid)
            }
        }
        .navigationDestination(isPresented: $isShowingSettings) {
            SettingsDetailView()
        }
        .navigationDestination(isPresented: $isShowingSubscriptions) {
            SubscriptionsView()
        }
        .navigationDestination(isPresented: $isShowingDevices) {
            DevicesView()
        }
        .fullScreenCover(item: $editingProfile) { ProfileEditorView(profile: $0) }
        .fullScreenCover(isPresented: $isShowingManageProfiles) { ManageProfilesView() }
        .sheet(isPresented: $isShowingAboutService) {
            AboutServiceSheet()
        }
        .fullScreenCover(isPresented: $isShowingCreateProfile) {
            ProfileEditorView()
        }
        .alert("Sign Out", isPresented: $isShowingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                HapticManager.shared.notification(.warning)
                do { try appState.signOut() }
                catch { signOutError = error.localizedDescription }
            }
        } message: {
            Text("Are you sure you want to sign out of Mirror?")
        }
    }

    // MARK: - Menu Card (Behance Board 18)
    private func accountMenuCard(title: String, icon: PhosphorIcon, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            VStack(spacing: 12) {
                PhosphorView(icon, size: 24, color: Color.mirrorInk)
                    .frame(width: 40, height: 40)
                    .background(Color.mirrorSurface3, in: RoundedRectangle(cornerRadius: 12))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.mirrorInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.mirrorSurface1)
            .cornerRadius(14)
        }
    }

}

// MARK: - About Service Sheet (Behance Board 01)
struct AboutServiceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(mirrorHex: "121215").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("About Mirror")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.mirrorInk)
                    Spacer()
                    Button(action: { dismiss() }) {
                        PhosphorView(.close, size: 14)
                            .foregroundColor(Color.mirrorInk.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.mirrorInk.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.top, Spacing.md)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Mirror is a modern cinema streaming client built with SwiftUI, Firebase, and peer-to-peer torrent streaming.")
                        .font(.system(size: 14))
                        .foregroundColor(Color.mirrorInk.opacity(0.75))
                        .lineSpacing(4)

                    Text("Version 1.0.0 (Build 2026)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.mirrorTextTertiary)
                }
                .padding(18)
                .background(Color(mirrorHex: "18181B"))
                .cornerRadius(16)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
        }
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }
}
