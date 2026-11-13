import SwiftUI
import PhotosUI
import ImageIO

struct ProfileAvatarView: View {
    let profile: MirrorUserProfile
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: profile.avatarColor))
            if let encoded = profile.avatarImage, let data = Data(base64Encoded: encoded), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                PhosphorView(profile.isKid ? .smiley : .userFill, size: size * 0.43)
                    .foregroundStyle(Color.mirrorInk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("\(profile.name)'s avatar")
    }
}

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    private let profile: MirrorUserProfile?
    @State private var name: String
    @State private var isKid: Bool
    @State private var avatarColor: String
    @State private var avatarImage: String?
    @State private var photo: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    init(profile: MirrorUserProfile? = nil) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _isKid = State(initialValue: profile?.isKid ?? false)
        _avatarColor = State(initialValue: profile?.avatarColor ?? "222226")
        _avatarImage = State(initialValue: profile?.avatarImage)
    }

    private var draft: MirrorUserProfile {
        MirrorUserProfile(name: name, isKid: isKid, avatarColor: avatarColor, avatarImage: avatarImage)
    }

    @State private var isChoosingAvatar = false

    var body: some View {
        VStack(spacing: 0) {
            ProfileScreenHeader(title: profile == nil ? "Create Profile" : "Edit Profile") { dismiss() }
                .disabled(isSaving)
            ScrollView {
                VStack(spacing: 0) {
                    Button { photo = nil; isChoosingAvatar = true } label: {
                        ProfileAvatarView(profile: draft, size: 112)
                            .overlay {
                                Circle().fill(.black.opacity(0.16))
                                PhosphorView(.editLinear, size: 24, color: Color.mirrorInk)
                            }
                    }
                    .accessibilityLabel("Change profile photo")
                    .disabled(isSaving || isLoadingPhoto)
                    .padding(.top, 24)
                    Text(name.isEmpty ? "Profile name" : name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(name.isEmpty ? Color.mirrorTextTertiary : Color.mirrorInk)
                        .padding(.top, 10)
                    if isLoadingPhoto { ProgressView().padding(.top, 10) }
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            if profile != nil {
                                Text("Profile name").font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary)
                            }
                            TextField("Profile name", text: $name)
                                .font(.system(size: 14))
                                .textContentType(.nickname)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Kids profile", isOn: $isKid)
                                .toggleStyle(ProfileToggleStyle())
                                .padding(.horizontal, 16)
                                .frame(height: 52)
                                .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 12))
                            Text("Turn on for kid-friendly content")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mirrorTextTertiary)
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.system(size: 13)).foregroundStyle(Color.mirrorRed)
                        }
                    }
                    .padding(.top, 40)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
                .disabled(isSaving)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.mirrorBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 24) {
                if profile != nil {
                    Button { confirmDelete = true } label: {
                        HStack(spacing: 6) {
                            PhosphorView(.trash, size: 16, color: .mirrorRed)
                            Text("Delete Profile").font(.system(size: 13))
                        }
                        .foregroundStyle(Color.mirrorRed)
                    }
                    .disabled(isSaving || AuthService.shared.profiles.count <= 1)
                    .opacity(AuthService.shared.profiles.count > 1 ? 1 : 0.4)
                }
                Button(action: save) {
                    Group {
                        if isSaving { ProgressView().tint(Color.mirrorOnInk) }
                        else { Text(profile == nil ? "Create" : "Save changes").font(.system(size: 14, weight: .semibold)) }
                    }
                    .foregroundStyle(Color.mirrorOnInk)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.mirrorInk, in: Capsule())
                }
                .disabled(isSaving || isLoadingPhoto || !(1...30).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count))
                .opacity((1...30).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count) ? 1 : 0.4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .background(Color.mirrorBackground)
        }
        .confirmationDialog("Delete \(profile?.name ?? "profile")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This profile and its photo will be removed from your account.") }
        .fullScreenCover(isPresented: $isChoosingAvatar) {
            AvatarSelectionView(photo: $photo, hasPhoto: avatarImage != nil) { image in
                do { avatarImage = try AvatarPhotoEncoder.encode(image); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
            } onRemove: {
                avatarImage = nil
                photo = nil
            }
        }
        .task(id: photo) {
            guard let photo else { isLoadingPhoto = false; return }
            isLoadingPhoto = true
            defer { if self.photo == photo { isLoadingPhoto = false } }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { throw ProfileError.invalidImage }
                try Task.checkCancellation()
                guard self.photo == photo else { return }
                avatarImage = try AvatarPhotoEncoder.encode(data)
                errorMessage = nil
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
        .tint(.mirrorAccent)

        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                if let profile {
                    try await AuthService.shared.updateProfile(id: profile.id, name: name, isKid: isKid, avatarColor: avatarColor, avatarImage: avatarImage)
                } else {
                    try await AuthService.shared.addProfile(name: name, isKid: isKid, avatarColor: avatarColor, avatarImage: avatarImage)
                }
                HapticManager.shared.notification(.success)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func delete() {
        guard let profile else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await AuthService.shared.deleteProfile(id: profile.id)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct ProfileScreenHeader: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 20, weight: .medium)).foregroundStyle(Color.mirrorInk)
            HStack {
                Button(action: onBack) {
                    PhosphorView(.caretLeft, size: 18)
                        .foregroundStyle(Color.mirrorInk)
                        .frame(width: 40, height: 40)
                        .background(Color.mirrorSurface1, in: Circle())
                }
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct ProfileToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label.font(.system(size: 14)).foregroundStyle(Color.mirrorInk)
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Color.mirrorInk : Color.mirrorInk.opacity(0.07))
                    .frame(width: 46, height: 28)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? Color.mirrorOnInk : Color.mirrorInk)
                            .frame(width: 24, height: 24).padding(2)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityHint("Double tap to toggle")
    }
}

struct ManageProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile: MirrorUserProfile?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 24) {
            ProfileScreenHeader(title: "Manage profiles") { dismiss() }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(AuthService.shared.profiles) { profile in
                        Button { editingProfile = profile } label: {
                            HStack(spacing: 14) {
                                ProfileAvatarView(profile: profile, size: 52)
                                Text(profile.name).font(.system(size: 14)).foregroundStyle(Color.mirrorInk)
                                Spacer()
                                PhosphorView(.editLinear, size: 18, color: .mirrorTextSecondary)
                            }
                            .padding(16)
                            .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    Button { isCreating = true } label: {
                        Label { Text("Add profile") } icon: { PhosphorView(.add, size: 14) }.font(.system(size: 14))
                            .foregroundStyle(Color.mirrorTextSecondary)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color.mirrorBackground.ignoresSafeArea())
        .fullScreenCover(item: $editingProfile) { ProfileEditorView(profile: $0) }
        .fullScreenCover(isPresented: $isCreating) { ProfileEditorView() }
        .tint(.mirrorAccent)

    }
}
