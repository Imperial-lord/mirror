import AppKit
import SwiftUI

struct DesktopAccountView: View {
  @Environment(DesktopSession.self) private var session
  @State private var confirmSignOut = false
  @State private var error: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 30) {
        DesktopPageHeader(title: "Your space", subtitle: "A profile for every kind of movie night.")
        if let user = AuthService.shared.currentUser {
          HStack(spacing: 22) {
            DesktopAvatar(profile: AuthService.shared.currentProfile).frame(width: 83, height: 83)
            VStack(alignment: .leading, spacing: 7) {
              Text(AuthService.shared.currentProfile?.name ?? user.displayName ?? "Your account")
                .font(.title2.weight(.semibold))
              Text(user.email ?? "").foregroundStyle(Color.mirrorTextSecondary).textSelection(
                .enabled)
            }
            Spacer()
            DesktopAction(title: "Switch profile") { session.showProfiles = true }
          }.desktopPanel()
          Text("Profiles").font(.title3.weight(.semibold))
          HStack(spacing: 22) {
            ForEach(AuthService.shared.profiles) { profile in
              Button {
                AuthService.shared.selectProfile(profile)
              } label: {
                VStack(spacing: 12) {
                  DesktopAvatar(profile: profile).frame(width: 70, height: 70)
                    .overlay(
                      Circle().stroke(
                        profile.id == AuthService.shared.currentProfile?.id
                          ? Color.mirrorInk : .clear, lineWidth: 2))
                  Text(profile.name).font(.system(size: 13, weight: .medium))
                  Text(profile.isKid ? "Kids profile" : "Profile").font(.caption).foregroundStyle(
                    Color.mirrorTextTertiary)
                }.frame(width: 130).padding(.vertical, 20).background(
                  Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 16))
              }.buttonStyle(.plain)
            }
            DesktopAction(title: "Manage profiles", icon: .editLinear) {
              session.showProfiles = true
            }
          }
          VStack(alignment: .leading, spacing: 18) {
            Text("This device").font(.headline)
            HStack(spacing: 16) {
              PhosphorView(.monitorLinear, size: 29)
              VStack(alignment: .leading, spacing: 5) {
                Text(Host.current().localizedName ?? "This Mac").fontWeight(.medium)
                Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)").font(.caption)
                  .foregroundStyle(Color.mirrorTextTertiary)
              }
            }
          }.desktopPanel()
          DesktopAction(title: "Sign out", icon: .logoutLinear) { confirmSignOut = true }
        } else {
          DesktopEmpty(
            title: "Welcome to your space",
            message: "Sign in to sync your profiles, playlists and watch history.",
            icon: .profileLinear)
          DesktopAction(title: "Sign in", primary: true) { session.showSignIn = true }.frame(
            maxWidth: .infinity)
        }
        if let error { Text(error).foregroundStyle(Color.mirrorRed) }
      }.padding(38).padding(.top, 14).frame(maxWidth: 1000, alignment: .leading).frame(
        maxWidth: .infinity, alignment: .leading)
    }.background(Color.mirrorBackground)
      .alert("Sign out of Mirror?", isPresented: $confirmSignOut) {
        Button("Sign out", role: .destructive) {
          do {
            try AuthService.shared.signOut()
            session.navigate(.home)
            session.browsing = false
          } catch { self.error = error.localizedDescription }
        }
        Button("Cancel", role: .cancel) {}
      }
  }
}

struct DesktopSettingsView: View {
  @AppStorage("mirrorTheme") private var theme = DesktopTheme.dark.rawValue
  @AppStorage("autoplay") private var autoplay = true
  @State private var deleteDownloads = false
  @State private var error: String?
  @State private var usage: (downloads: Int64, used: Int64, free: Int64) = (0, 0, 0)
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 30) {
        DesktopPageHeader(title: "Settings", subtitle: "Make yourself comfortable.")
        VStack(alignment: .leading, spacing: 20) {
          Text("Appearance").font(.headline)
          HStack(spacing: 14) {
            ForEach(DesktopTheme.allCases, id: \.rawValue) { mode in
              Button {
                theme = mode.rawValue
              } label: {
                VStack(spacing: 12) {
                  PhosphorView(
                    mode == .system ? .monitorLinear : mode == .light ? .sun : .moon, size: 25)
                  Text(mode.rawValue.capitalized).font(.system(size: 13, weight: .medium))
                }.frame(maxWidth: .infinity).frame(height: 95)
                  .background(
                    theme == mode.rawValue ? Color.mirrorSurface3 : .mirrorSurface2,
                    in: RoundedRectangle(cornerRadius: 14)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 14).stroke(
                      Color.mirrorInk.opacity(theme == mode.rawValue ? 0.5 : 0.05)))
              }.buttonStyle(.plain)
            }
          }
        }.desktopPanel()
        VStack(alignment: .leading, spacing: 15) {
          Text("Player").font(.headline)
          Toggle(isOn: $autoplay) {
            VStack(alignment: .leading, spacing: 5) {
              Text("Autoplay")
              Text("Start playing as soon as your movie is ready.").font(.caption).foregroundStyle(
                Color.mirrorTextTertiary)
            }
          }.toggleStyle(.switch).tint(Color.mirrorInk)
          Divider().overlay(Color.mirrorInk.opacity(0.1))
          Text("Space to pause · ← / → to skip 10 seconds · F for full screen · Esc to go back")
            .font(.caption).foregroundStyle(Color.mirrorTextSecondary)
        }.desktopPanel()
        VStack(alignment: .leading, spacing: 20) {
          HStack {
            Text("Storage on this Mac").font(.headline)
            Spacer()
            Text(bytes(usage.free) + " available").font(.caption).foregroundStyle(
              Color.mirrorTextTertiary)
          }
          GeometryReader { box in
            let total = max(1, usage.used + usage.free)
            ZStack(alignment: .leading) {
              Capsule().fill(Color.mirrorSurface3)
              Capsule().fill(Color.mirrorInk.opacity(0.3)).frame(
                width: box.size.width * Double(usage.used) / Double(total))
              Capsule().fill(Color.mirrorInk).frame(
                width: max(
                  usage.downloads > 0 ? 4 : 0,
                  box.size.width * Double(usage.downloads) / Double(total)))
            }
          }.frame(height: 7)
          HStack {
            storageValue("Mirror downloads", value: bytes(usage.downloads))
            Spacer()
            storageValue("Other files", value: bytes(max(0, usage.used - usage.downloads)))
            Spacer()
            storageValue("Available", value: bytes(usage.free))
          }
          Button("Delete all downloads") { deleteDownloads = true }.buttonStyle(.plain)
            .foregroundStyle(Color.mirrorRed).disabled(DownloadStore.shared.records.isEmpty)
        }.desktopPanel()
        HStack {
          VStack(alignment: .leading, spacing: 7) {
            Text("Mirror for Mac").font(.headline)
            Text("Version 1.0 · Stories, without distractions.").font(.caption).foregroundStyle(
              Color.mirrorTextTertiary)
          }
          Spacer()
          Link(
            "Project & licenses",
            destination: URL(string: "https://github.com/Imperial-lord/mirror")!
          ).font(.caption).foregroundStyle(Color.mirrorTextSecondary)
        }.desktopPanel()
        if let error { Text(error).foregroundStyle(Color.mirrorRed) }
      }.padding(38).padding(.top, 14).frame(maxWidth: 950, alignment: .leading).frame(
        maxWidth: .infinity, alignment: .leading)
    }.background(Color.mirrorBackground).onAppear { refreshStorage() }
      .onChange(of: DownloadStore.shared.records.map { "\($0.id)-\($0.status.rawValue)" }) { _, _ in
        refreshStorage()
      }
      .alert("Delete all downloads?", isPresented: $deleteDownloads) {
        Button("Delete all", role: .destructive) {
          do {
            try DownloadStore.shared.deleteAll()
            refreshStorage()
          } catch { self.error = error.localizedDescription }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Saved videos and subtitles will be removed from this Mac. Your Favorites and watch history will stay."
        )
      }
  }
  private func refreshStorage() {
    usage = DownloadStore.shared.diskUsage()
    if usage.used + usage.free == 0,
      let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
    {
      let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
      let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
      usage = (0, total - free, free)
    }
  }
  private func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }
  private func storageValue(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption).foregroundStyle(Color.mirrorTextTertiary)
      Text(value).font(.system(size: 16, weight: .medium)).monospacedDigit()
    }
  }
}
