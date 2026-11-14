import AppKit
import SwiftData
import SwiftUI

struct DesktopRootView: View {
  @Environment(DesktopSession.self) private var session
  @Environment(\.modelContext) private var context
  @State private var launched = false
  private let auth = AuthService.shared
  var body: some View {
    @Bindable var session = session
    ZStack {
      if launched {
        if auth.isAuthenticated || session.browsing {
          ZStack {
            shell.allowsHitTesting(session.playback == nil).accessibilityHidden(
              session.playback != nil)
            if session.playback != nil { DesktopPlayerView() }
          }
        } else {
          DesktopAuthView(onComplete: { session.showProfiles = true })
        }
      } else {
        VStack(spacing: 14) {
          Text("mirror").font(.system(size: 68, weight: .bold)).kerning(-4)
          Text("A world of stories.").font(.callout).foregroundStyle(Color.mirrorTextSecondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.mirrorBackground).foregroundStyle(Color.mirrorInk)
    .tint(Color.mirrorInk)
    .task {
      LibraryStore.shared.start()
      DownloadStore.shared.start()
      try? await Task.sleep(for: .milliseconds(700))
      launched = true
    }
    .task(id: auth.currentUser?.uid) {
      if auth.isAuthenticated { _ = await WatchHistorySync.sync(context: context) }
    }
    .onChange(of: auth.currentUser?.uid) { _, uid in
      if uid == nil {
        session.playback = nil
        session.path = NavigationPath()
      }
    }
    .sheet(isPresented: $session.showSignIn) {
      DesktopAuthView(onComplete: {
        session.showSignIn = false
        session.showProfiles = true
      }).frame(width: 900, height: 650)
    }
    .sheet(isPresented: $session.showProfiles) {
      DesktopProfilesView().frame(width: 780, height: 540)
    }
    .alert(
      "Mirror",
      isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })
    ) {
      Button("OK") { session.error = nil }
    } message: {
      Text(session.error ?? "")
    }
  }
  private var shell: some View {
    HStack(spacing: 0) {
      sidebar.frame(width: 218)
      Rectangle().fill(Color.mirrorInk.opacity(0.07)).frame(width: 1)
      NavigationStack(path: Binding(get: { session.path }, set: { session.path = $0 })) {
        Group {
          switch session.section {
          case .home: DesktopHomeView()
          case .catalog: DesktopCatalogView()
          case .library: DesktopLibraryView()
          case .downloads: DesktopDownloadsView()
          case .account: DesktopAccountView()
          case .settings: DesktopSettingsView()
          }
        }
        .navigationDestination(for: DesktopRoute.self) { route in
          Group {
            switch route {
            case .movie(let id): DesktopMovieView(movieID: id)
            case .person(let person): DesktopPersonView(person: person)
            case .collection(let title, let ids): DesktopCollectionView(title: title, ids: ids)
            }
          }.toolbar(.hidden, for: .windowToolbar)
        }
        .toolbar(.hidden, for: .windowToolbar)
      }
      .toolbar(.hidden, for: .windowToolbar)
    }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("mirror").font(.system(size: 34, weight: .bold)).kerning(-2)
        .padding(.top, 54).padding(.bottom, 45).padding(.leading, 28)
      Text("DISCOVER").font(.system(size: 10, weight: .semibold)).tracking(2)
        .foregroundStyle(Color.mirrorTextTertiary).padding(.leading, 28).padding(.bottom, 15)
      ForEach([DesktopSection.home, .catalog, .library, .downloads]) { item in sideRow(item) }
      Spacer(minLength: 40)
      sideRow(.settings)
      Button {
        if auth.isAuthenticated { session.navigate(.account) } else { session.showSignIn = true }
      } label: {
        HStack(spacing: 10) {
          DesktopAvatar(profile: auth.currentProfile).frame(width: 34, height: 34)
          VStack(alignment: .leading, spacing: 3) {
            Text(auth.currentProfile?.name ?? "Welcome to Mirror").font(
              .system(size: 12, weight: .semibold)
            ).lineLimit(1)
            Text(auth.isAuthenticated ? "Manage your account" : "Sign in to your account").font(
              .system(size: 10)
            ).foregroundStyle(Color.mirrorTextTertiary)
          }
          Spacer(minLength: 0)
        }.padding(12).background(
          session.section == .account ? Color.mirrorSurface2 : .clear,
          in: RoundedRectangle(cornerRadius: 12))
      }.buttonStyle(.plain).padding(16)
    }.background(Color.mirrorBackground)
  }
  private func sideRow(_ item: DesktopSection) -> some View {
    Button {
      session.navigate(item)
    } label: {
      HStack(spacing: 13) {
        PhosphorView(
          item.icon, size: 20, color: session.section == item ? .mirrorInk : .mirrorTextSecondary)
        Text(item.rawValue).font(
          .system(size: 13, weight: session.section == item ? .semibold : .regular))
        Spacer()
        if item == .downloads, !DownloadStore.shared.records.isEmpty {
          Text(String(DownloadStore.shared.records.count)).font(
            .system(size: 10, weight: .semibold)
          )
          .padding(5).background(Color.mirrorSurface3, in: Circle())
        }
      }.padding(.horizontal, 15).frame(height: 46)
        .foregroundStyle(session.section == item ? Color.mirrorInk : .mirrorTextSecondary)
        .background(
          session.section == item ? Color.mirrorSurface2 : .clear,
          in: RoundedRectangle(cornerRadius: 11)
        )
        .contentShape(Rectangle())
    }.buttonStyle(.plain).padding(.horizontal, 15).padding(.bottom, 5)
  }
}

struct DesktopPageHeader: View {
  let title: String
  var subtitle: String? = nil
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 30, weight: .semibold)).tracking(-0.7)
        if let subtitle { Text(subtitle).font(.callout).foregroundStyle(Color.mirrorTextSecondary) }
      }
      Spacer()
    }.padding(.bottom, 12)
  }
}

struct DesktopAvatar: View {
  let profile: MirrorUserProfile?
  var body: some View {
    Group {
      if let data = profile?.avatarImage.flatMap({ Data(base64Encoded: $0) }),
        let image = NSImage(data: data)
      {
        Image(nsImage: image).resizable().scaledToFill()
      } else if let preset = profile?.avatarColor, preset.hasPrefix("preset:") {
        Image(String(preset.dropFirst(7))).resizable().scaledToFill()
      } else {
        Color.mirrorSurface3.overlay {
          PhosphorView(
            profile?.isKid == true ? .smiley : .userFill, size: 25, color: .mirrorTextSecondary)
        }
      }
    }.clipShape(Circle())
  }
}
