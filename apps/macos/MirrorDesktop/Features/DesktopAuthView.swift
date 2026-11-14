import AppKit
import FirebaseAuth
import SwiftUI

struct DesktopAuthView: View {
  @Environment(DesktopSession.self) private var session
  @Environment(\.dismiss) private var dismiss
  var onComplete: () -> Void
  @State private var signUp = false
  @State private var email = ""
  @State private var password = ""
  @State private var name = ""
  @State private var verification = false
  @State private var code = ""
  @State private var working = false
  @State private var message: String?
  @State private var reset = false
  @State private var posters: [Movie] = []
  var body: some View {
    HStack(spacing: 0) {
      ZStack(alignment: .bottomLeading) {
        Color.mirrorSurface1
        GeometryReader { box in
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16
          ) {
            ForEach(posters.prefix(12)) { movie in
              DesktopImage(url: movie.posterURL).frame(height: box.size.width * 0.47)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
          }.rotationEffect(.degrees(-12)).scaleEffect(1.18).offset(y: -65)
        }.opacity(0.5).clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 24) {
          Text("mirror").font(.system(size: 52, weight: .bold)).kerning(-3)
          Spacer()
          Text("Great stories.\nYour own space.").font(.system(size: 42, weight: .semibold))
            .tracking(-1.5)
          Text(
            "Discover your next favorite. Pick up where you left off. Take a few stories with you."
          )
          .font(.system(size: 15)).foregroundStyle(.white.opacity(0.62)).lineSpacing(5)
        }.padding(48).foregroundStyle(.white)
      }.frame(maxWidth: .infinity)
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Spacer()
          if session.showSignIn {
            Button {
              dismiss()
            } label: {
              PhosphorView(.close, size: 18)
            }.buttonStyle(.plain).help("Close")
          }
        }
        Spacer()
        Text(
          verification
            ? "Check your email"
            : reset ? "Reset password" : signUp ? "Create your account" : "Welcome back"
        )
        .font(.system(size: 29, weight: .semibold)).tracking(-0.6)
        Text(
          verification
            ? "Enter a four-digit code to continue." : "Your next favorite movie is waiting."
        )
        .foregroundStyle(Color.mirrorTextSecondary)
        if verification {
          TextField("0000", text: $code).desktopField()
            .onChange(of: code) { _, value in
              code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
            }
        } else {
          if signUp && !reset { TextField("Your name", text: $name).desktopField() }
          TextField("Email address", text: $email).desktopField().textContentType(.emailAddress)
          if !reset {
            SecureField(signUp ? "Create password" : "Password", text: $password).desktopField()
              .onSubmit { submit() }
          }
        }
        if let message {
          Text(message).font(.caption).foregroundStyle(Color.mirrorTextSecondary).fixedSize(
            horizontal: false, vertical: true)
        }
        Button(action: submit) {
          HStack {
            Spacer()
            if working { ProgressView().controlSize(.small).tint(Color.mirrorOnInk) }
            Text(
              verification
                ? "Verify account"
                : reset ? "Send reset link" : signUp ? "Create account" : "Sign in"
            ).fontWeight(.semibold)
            Spacer()
          }.frame(height: 45).foregroundStyle(Color.mirrorOnInk).background(
            Color.mirrorInk, in: Capsule())
        }.buttonStyle(.plain).disabled(working)
        if !verification && !reset {
          HStack(spacing: 12) {
            Rectangle().frame(height: 1)
            Text("or").font(.caption)
            Rectangle().frame(height: 1)
          }.foregroundStyle(Color.mirrorTextTertiary)
          HStack {
            DesktopAction(title: "Continue with Google", icon: .googleLogo) {
              working = true
              message = nil
              Task {
                do {
                  _ = try await AuthService.shared.signInWithGoogle()
                  onComplete()
                } catch { message = DesktopAuthError.message(error) }
                working = false
              }
            }.disabled(working)
            Button {
            } label: {
              PhosphorView(.appleLogo, size: 20).frame(width: 43, height: 43).background(
                Color.mirrorSurface2, in: Circle())
            }.buttonStyle(.plain)
          }
          HStack {
            Button(signUp ? "Already have an account? Sign in" : "New to Mirror? Sign up") {
              signUp.toggle()
              message = nil
            }.buttonStyle(.plain)
            Spacer()
            if !signUp {
              Button("Forgot password?") {
                reset = true
                message = nil
              }.buttonStyle(.plain)
            }
          }.font(.system(size: 11)).foregroundStyle(Color.mirrorTextSecondary)
        } else {
          Button("Back to sign in") {
            verification = false
            reset = false
            signUp = false
            message = nil
          }.buttonStyle(.plain)
        }
        Spacer()
        Button("Browse movies") {
          session.browsing = true
          session.showSignIn = false
        }.buttonStyle(.plain).foregroundStyle(Color.mirrorTextSecondary)
      }.padding(48).frame(width: 470)
    }.background(Color.mirrorBackground).foregroundStyle(Color.mirrorInk)
      .task {
        posters =
          (try? await MovieRepository.shared.fetchMovies(
            endpoint: .listMovies(limit: 15, sortBy: "like_count"))) ?? []
      }
  }
  private func submit() {
    guard !working else { return }
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard email.contains("@"), email.contains(".") else {
      message = "Enter a valid email address."
      return
    }
    if reset {
      working = true
      Task {
        do {
          try await AuthService.shared.sendPasswordReset(email: email)
          message = "If an account exists, a reset link is on its way."
        } catch { message = DesktopAuthError.message(error) }
        working = false
      }
      return
    }
    guard !password.isEmpty, !signUp || password.count >= 6 else {
      message = "Use a password with at least six characters."
      return
    }
    if signUp && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      message = "Enter your name."
      return
    }
    if signUp && !verification {
      verification = true
      message = nil
      return
    }
    if verification && code.count != 4 {
      message = "Enter four digits."
      return
    }
    working = true
    message = nil
    Task {
      do {
        if signUp {
          try await AuthService.shared.signUp(email: email, password: password, username: name)
        } else {
          try await AuthService.shared.signIn(email: email, password: password)
        }
        onComplete()
      } catch { message = DesktopAuthError.message(error) }
      working = false
    }
  }
}

private enum DesktopAuthError {
  static func message(_ error: Error) -> String {
    let code = AuthErrorCode(rawValue: (error as NSError).code)
    switch code {
    case .wrongPassword, .invalidCredential, .userNotFound:
      return "The email or password isn’t correct. Please try again."
    case .emailAlreadyInUse: return "An account with this email already exists. Sign in instead."
    case .invalidEmail: return "Enter a valid email address."
    case .weakPassword: return "Choose a password with at least six characters."
    case .networkError: return "Check your internet connection and try again."
    case .keychainError: return "Mirror couldn’t save your session. Reopen the app and try again."
    case .tooManyRequests: return "Please wait a moment before trying again."
    default: return error.localizedDescription
    }
  }
}

struct DesktopProfilesView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var editing: MirrorUserProfile?
  @State private var create = false
  var body: some View {
    VStack(spacing: 30) {
      HStack {
        Spacer()
        DesktopIconButton(icon: .close, help: "Close") { dismiss() }
      }
      Text("Who’s watching?").font(.system(size: 30, weight: .semibold))
      if AuthService.shared.isLoadingProfiles { ProgressView() }
      HStack(spacing: 28) {
        ForEach(AuthService.shared.profiles) { profile in
          VStack(spacing: 12) {
            Button {
              AuthService.shared.selectProfile(profile)
              dismiss()
            } label: {
              DesktopAvatar(profile: profile).frame(width: 88, height: 88)
                .overlay(
                  Circle().stroke(
                    profile.id == AuthService.shared.currentProfile?.id ? Color.mirrorInk : .clear,
                    lineWidth: 2))
            }.buttonStyle(.plain).help("Watch as \(profile.name)")
            Text(profile.name).fontWeight(.medium)
            Button("Edit") { editing = profile }.buttonStyle(.plain).foregroundStyle(
              Color.mirrorTextSecondary
            ).font(.caption)
          }
        }
        VStack(spacing: 12) {
          Button {
            create = true
          } label: {
            PhosphorView(.add, size: 24).frame(width: 88, height: 88).overlay(
              Circle().stroke(Color.mirrorTextTertiary))
          }.buttonStyle(.plain)
          Text("Add profile")
        }
      }.frame(maxHeight: .infinity)
    }.padding(32).background(Color.mirrorBackground).foregroundStyle(Color.mirrorInk)
      .sheet(item: $editing) { DesktopProfileEditor(profile: $0) }
      .sheet(isPresented: $create) { DesktopProfileEditor(profile: nil) }
  }
}

struct DesktopProfileEditor: View {
  let profile: MirrorUserProfile?
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var kid = false
  @State private var avatar = "222226"
  @State private var photo: String?
  @State private var message: String?
  @State private var working = false
  @State private var confirmDelete = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(profile == nil ? "Create a profile" : "Edit profile").font(.title2.weight(.semibold))
      HStack(spacing: 20) {
        DesktopAvatar(
          profile: MirrorUserProfile(name: name, avatarColor: avatar, avatarImage: photo)
        ).frame(width: 76, height: 76)
        DesktopAction(title: "Choose photo", icon: .photo, action: choosePhoto)
        Button("Remove photo") { photo = nil }.buttonStyle(.plain).disabled(photo == nil)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 9) {
          ForEach(0..<16, id: \.self) { index in
            Button {
              if let image = NSImage(named: "AvatarPreset\(index)") { encodePhoto(image) }
            } label: {
              Image("AvatarPreset\(index)").resizable().scaledToFill().frame(width: 42, height: 42)
                .clipShape(Circle())
            }.buttonStyle(.plain)
          }
        }
      }
      TextField("Profile name", text: $name).desktopField()
      Toggle("Kids profile", isOn: $kid).tint(Color.mirrorInk)
      if let message { Text(message).font(.caption).foregroundStyle(Color.mirrorRed) }
      HStack {
        if let profile, AuthService.shared.profiles.count > 1 {
          Button("Delete profile") { confirmDelete = true }.foregroundStyle(Color.mirrorRed)
            .buttonStyle(.plain)
        }
        Spacer()
        DesktopAction(title: "Cancel") { dismiss() }
        DesktopAction(title: "Save", primary: true, action: save).disabled(working)
      }
    }.padding(30).frame(width: 520).background(Color.mirrorBackground).foregroundStyle(
      Color.mirrorInk
    )
    .onAppear {
      if let profile {
        name = profile.name
        kid = profile.isKid
        avatar = profile.avatarColor
        photo = profile.avatarImage
      }
    }
    .alert("Delete this profile?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive) {
        Task {
          do {
            try await AuthService.shared.deleteProfile(id: profile!.id)
            dismiss()
          } catch { message = error.localizedDescription }
        }
      }
      Button("Cancel", role: .cancel) {}
    }
  }
  private func save() {
    working = true
    Task {
      do {
        if let profile {
          try await AuthService.shared.updateProfile(
            id: profile.id, name: name, isKid: kid, avatarColor: avatar, avatarImage: photo)
        } else {
          try await AuthService.shared.addProfile(
            name: name, isKid: kid, avatarColor: avatar, avatarImage: photo)
        }
        dismiss()
      } catch { message = error.localizedDescription }
      working = false
    }
  }
  private func choosePhoto() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else {
      return
    }
    encodePhoto(image)
  }
  private func encodePhoto(_ image: NSImage) {
    let size = NSSize(width: 384, height: 384)
    let resized = NSImage(size: size)
    resized.lockFocus()
    let scale = max(384 / max(1, image.size.width), 384 / max(1, image.size.height))
    let scaled = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    image.draw(
      in: NSRect(
        x: (384 - scaled.width) / 2, y: (384 - scaled.height) / 2, width: scaled.width,
        height: scaled.height))
    resized.unlockFocus()
    guard let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]),
      data.count < 200_000
    else {
      message = "Choose a smaller photo."
      return
    }
    photo = data.base64EncodedString()
  }
}
