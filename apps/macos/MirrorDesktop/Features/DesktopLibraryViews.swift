import AppKit
import SwiftData
import SwiftUI

struct DesktopLibraryView: View {
  @Environment(DesktopSession.self) private var session
  @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var history:
    [WatchHistoryItem]
  @State private var tab = "Recent"
  @State private var folder: String?
  @State private var create = false
  @State private var name = ""
  @State private var editList: LibraryPlaylist?
  @State private var renameList: LibraryPlaylist?
  @State private var deleteList: LibraryPlaylist?
  @State private var error: String?
  private let store = LibraryStore.shared
  private var owned: [WatchHistoryItem] {
    history.filter { $0.userId == AuthService.shared.currentUser?.uid }
  }
  private var watched: [WatchHistoryItem] { LibraryHistory.movies(in: .watched, from: owned) }
  private var progress: [WatchHistoryItem] { LibraryHistory.movies(in: .continuing, from: owned) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 30) {
        DesktopPageHeader(
          title: "Library", subtitle: "The stories you keep. The ones you come back to.")
        if !AuthService.shared.isAuthenticated {
          DesktopEmpty(
            title: "Make it your own",
            message: "Sign in to find your saved movies and watch history on every device.",
            icon: .bookmarkLinear)
          DesktopAction(title: "Sign in", primary: true) { session.showSignIn = true }.frame(
            maxWidth: .infinity)
        } else {
          Picker("Library", selection: $tab) {
            Text("Recent").tag("Recent")
            Text("Favorites").tag("Favorites")
          }.pickerStyle(.segmented).frame(width: 270).onChange(of: tab) { _, _ in folder = nil }
          if tab == "Recent" {
            recent
          } else if !store.loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 220)
          } else if let folder {
            folderContent(folder)
          } else {
            favorites
          }
          if let message = store.error { DesktopError(message: message) { store.retry() } }
        }
      }.padding(38).padding(.top, 14)
    }.background(Color.mirrorBackground)
      .alert("Create playlist", isPresented: $create) {
        TextField("Playlist name", text: $name)
        Button("Create") {
          Task {
            do {
              _ = try await store.create(name: name)
              name = ""
            } catch { self.error = error.localizedDescription }
          }
        }
        Button("Cancel", role: .cancel) {}
      }
      .alert(
        "Rename playlist",
        isPresented: Binding(get: { renameList != nil }, set: { if !$0 { renameList = nil } })
      ) {
        TextField("Playlist name", text: $name)
        Button("Save") {
          if let list = renameList {
            Task {
              do { try await store.rename(id: list.id, name: name) } catch {
                self.error = error.localizedDescription
              }
            }
          }
          renameList = nil
        }
        Button("Cancel", role: .cancel) { renameList = nil }
      }
      .alert(
        "Delete playlist?",
        isPresented: Binding(get: { deleteList != nil }, set: { if !$0 { deleteList = nil } })
      ) {
        Button("Delete", role: .destructive) {
          if let list = deleteList {
            Task {
              do {
                try await store.delete(id: list.id)
                folder = nil
              } catch { self.error = error.localizedDescription }
            }
          }
          deleteList = nil
        }
        Button("Cancel", role: .cancel) { deleteList = nil }
      } message: {
        Text("Your movies will stay in Favorites.")
      }
      .alert(
        "Library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("OK") { error = nil }
      } message: {
        Text(error ?? "")
      }
      .sheet(item: $editList) { DesktopPlaylistEditor(list: $0) }
  }
  private var recent: some View {
    VStack(alignment: .leading, spacing: 36) {
      if progress.isEmpty && watched.isEmpty {
        DesktopEmpty(
          title: "Your movie nights start here",
          message: "Movies you watch will appear here, ready to resume or revisit.", icon: .clock)
      }
      if !progress.isEmpty { DesktopContinueRow(items: progress) }
      if !watched.isEmpty {
        HStack {
          Text("Watched").font(.title3.weight(.semibold))
          Spacer()
          Button("View all") {
            session.path.append(DesktopRoute.collection("Watched", watched.map(\.movieId)))
          }.buttonStyle(.plain).font(.caption)
        }
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 155, maximum: 200), spacing: 22)], spacing: 26
        ) {
          ForEach(watched.prefix(10)) { item in
            Button {
              session.open(item.movieId)
            } label: {
              VStack(alignment: .leading, spacing: 9) {
                DesktopImage(url: URL(string: item.posterURL ?? "")).aspectRatio(
                  0.675, contentMode: .fit
                ).clipShape(RoundedRectangle(cornerRadius: 13))
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(
                  Color.mirrorTextTertiary)
              }
            }.buttonStyle(.plain)
          }
        }
        Text("Your watched genres").font(.title3.weight(.semibold))
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(LibraryHistory.genres(in: owned), id: \.self) { genre in
              DesktopAction(title: genre) {
                session.path.append(
                  DesktopRoute.collection(
                    "Watched · \(genre)",
                    LibraryHistory.movies(in: .genre(genre), from: owned).map(\.movieId)))
              }
            }
          }
        }.scrollIndicators(.hidden)
      }
    }
  }
  private var favorites: some View {
    VStack(alignment: .leading, spacing: 25) {
      HStack {
        Text("Favorites").font(.title3.weight(.semibold))
        Spacer()
        Button {
          folder = "favorites"
        } label: {
          PhosphorView(.caretRight, size: 15)
        }.buttonStyle(.plain).help("View all favorites")
      }
      if store.favorites.isEmpty {
        DesktopEmpty(
          title: "Keep your favorites close",
          message: "Save a movie from its detail page to start your collection.",
          icon: .bookmarkLinear)
      } else {
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: 18) {
            ForEach(store.favorites.prefix(12)) { savedCard($0, playlist: nil).frame(width: 157) }
          }
        }.scrollIndicators(.hidden)
      }
      HStack {
        Text("My playlists").font(.title3.weight(.semibold))
        Spacer()
        DesktopAction(title: "Add new", icon: .add) {
          name = ""
          create = true
        }
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 235, maximum: 360), spacing: 20)],
        alignment: .leading, spacing: 23
      ) {
        ForEach(store.playlists) { list in
          Button {
            folder = list.id
          } label: {
            VStack(alignment: .leading, spacing: 10) {
              ZStack {
                Color.mirrorSurface2
                if let first = store.movies(playlistID: list.id).first {
                  DesktopImage(url: URL(string: first.poster)).opacity(0.35)
                }
                PhosphorView(.folder, size: 43, color: .mirrorInk.opacity(0.7))
              }.frame(height: 138).clipShape(RoundedRectangle(cornerRadius: 15))
              HStack {
                Text(list.name).font(.system(size: 14, weight: .medium))
                Spacer()
                PhosphorView(.more, size: 15)
              }
              Text("\(list.movieIds.count) movies").font(.caption).foregroundStyle(
                Color.mirrorTextTertiary)
            }
          }.buttonStyle(.plain).contextMenu {
            Button("Edit movies") { editList = list }
            Button("Rename") {
              name = list.name
              renameList = list
            }
            Button("Delete playlist", role: .destructive) { deleteList = list }
          }
        }
      }
    }
  }
  private func folderContent(_ id: String) -> some View {
    let list = store.playlists.first { $0.id == id }
    return VStack(alignment: .leading, spacing: 24) {
      HStack {
        DesktopIconButton(icon: .arrowLeft, help: "Back to playlists") { folder = nil }
        Text(id == "favorites" ? "Favorites" : list?.name ?? "Playlist").font(
          .title2.weight(.semibold))
        Spacer()
        if let list { DesktopAction(title: "Edit movies", icon: .editLinear) { editList = list } }
      }
      let movies = store.movies(playlistID: id == "favorites" ? nil : id)
      if movies.isEmpty {
        DesktopEmpty(
          title: "A little room for your favorites",
          message: "Add movies from their detail pages or choose Edit movies.", icon: .folder)
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 22)],
        alignment: .leading, spacing: 28
      ) { ForEach(movies) { savedCard($0, playlist: id == "favorites" ? nil : id) } }
    }
  }
  private func savedCard(_ movie: SavedMovie, playlist: String?) -> some View {
    Button {
      session.open(movie.id)
    } label: {
      VStack(alignment: .leading, spacing: 9) {
        DesktopImage(url: URL(string: movie.poster)).aspectRatio(0.675, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 13))
        Text(movie.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
        Text(movie.subtitle).font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary)
      }
    }.buttonStyle(.plain).contextMenu {
      Button("Play movie") { session.play(movie.id) }
      Button(
        playlist == nil ? "Remove from Favorites and playlists" : "Remove from playlist",
        role: .destructive
      ) {
        Task {
          do { try await store.remove(movie: movie, from: playlist) } catch {
            self.error = error.localizedDescription
          }
        }
      }
    }
  }
}

struct DesktopPlaylistEditor: View {
  let list: LibraryPlaylist
  @Environment(\.dismiss) private var dismiss
  @State private var selected: Set<Int> = []
  @State private var error: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Edit \(list.name)").font(.title2.weight(.semibold))
      Text("Choose movies from your Favorites.").foregroundStyle(Color.mirrorTextSecondary)
      ScrollView {
        VStack(spacing: 8) {
          ForEach(LibraryStore.shared.favorites) { movie in
            Button {
              if selected.contains(movie.id) {
                selected.remove(movie.id)
              } else {
                selected.insert(movie.id)
              }
            } label: {
              HStack {
                DesktopImage(url: URL(string: movie.poster)).frame(width: 36, height: 50).clipShape(
                  RoundedRectangle(cornerRadius: 5))
                Text(movie.title)
                Spacer()
                DesktopSelectionMark(selected: selected.contains(movie.id))
              }.padding(9).background(Color.mirrorSurface2, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
          }
        }
      }.frame(height: 300)
      if let error { Text(error).font(.caption).foregroundStyle(Color.mirrorRed) }
      HStack {
        Spacer()
        DesktopAction(title: "Cancel") { dismiss() }
        DesktopAction(title: "Save", primary: true) {
          Task {
            do {
              try await LibraryStore.shared.setMovies(playlistID: list.id, movieIDs: selected)
              dismiss()
            } catch { self.error = error.localizedDescription }
          }
        }
      }
    }.padding(30).frame(width: 520).background(Color.mirrorBackground).foregroundStyle(
      Color.mirrorInk
    ).onAppear { selected = Set(list.movieIds) }
  }
}

struct DesktopSelectionMark: View {
  let selected: Bool
  var body: some View {
    PhosphorView(.check, size: 16).opacity(selected ? 1 : 0).padding(3).overlay(
      Circle().stroke(Color.mirrorInk.opacity(selected ? 1 : 0.35)))
  }
}

struct DesktopDownloadsView: View {
  @Environment(DesktopSession.self) private var session
  @State private var settings: MovieDetail?
  @State private var removing: OfflineDownload?
  @State private var error: String?
  private let store = DownloadStore.shared
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 25) {
        DesktopPageHeader(title: "Downloads", subtitle: "A few good movies. Wherever you go.")
        if store.records.isEmpty {
          DesktopEmpty(
            title: "Take a story with you",
            message:
              "Download a movie from its detail page. Choose its quality and subtitle languages before saving.",
            icon: .downloadLinear)
        }
        if let error = store.error { Text(error).foregroundStyle(Color.mirrorRed) }
        ForEach(store.records) { record in
          HStack(spacing: 20) {
            DesktopImage(url: store.poster(record)).frame(width: 62, height: 88).clipShape(
              RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 8) {
              Text(record.movie.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
              Text("\(record.quality) · \(record.size)").font(.caption).foregroundStyle(
                Color.mirrorTextTertiary)
              if record.status == .downloading || record.status == .preparing
                || record.status == .queued
              {
                ProgressView(value: record.progress).tint(Color.mirrorInk).frame(maxWidth: 330)
              }
              Text(status(record)).font(.caption).foregroundStyle(
                record.status == .failed ? Color.mirrorRed : .mirrorTextSecondary)
              if !record.notices.isEmpty {
                Text(record.notices.joined(separator: "\n")).font(.caption).foregroundStyle(
                  Color.mirrorTextTertiary)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if record.asset != nil {
              DesktopAction(title: "Play", icon: .playBold) { play(record) }
            }
            if [.downloading, .preparing, .queued].contains(record.status) {
              DesktopIconButton(icon: .pauseLinear, help: "Pause download") {
                store.pause(record.id)
              }
            }
            if [.paused, .failed].contains(record.status) {
              DesktopAction(title: record.status == .failed ? "Retry" : "Resume") {
                store.resume(record.id)
              }
            }
            Menu {
              Button("Download settings") { settings = record.movie }
              if record.asset != nil {
                Button("Show in Finder") {
                  if let file = try? store.playback(record).file {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                  }
                }
              }
              Button("Delete download", role: .destructive) { removing = record }
            } label: {
              PhosphorView(.more, size: 18)
            }.menuStyle(.borderlessButton).frame(width: 25).help("Download options")
          }.padding(21).background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 16))
        }
      }.padding(38).padding(.top, 14)
    }.background(Color.mirrorBackground)
      .sheet(item: $settings) { DesktopDownloadSheet(movie: $0) }
      .alert(
        "Delete download?",
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
      ) {
        Button("Delete", role: .destructive) {
          if let record = removing {
            do { try store.delete(record.id) } catch { self.error = error.localizedDescription }
          }
          removing = nil
        }
        Button("Cancel", role: .cancel) { removing = nil }
      } message: {
        Text("This removes the movie and its downloaded subtitles from this Mac.")
      }
      .alert(
        "Downloads", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("OK") { error = nil }
      } message: {
        Text(error ?? "")
      }
  }
  private func status(_ record: OfflineDownload) -> String {
    switch record.status {
    case .queued: return "Waiting to download"
    case .preparing: return "Preparing download…"
    case .downloading: return "Downloading \(Int(record.progress*100))%"
    case .paused: return "Paused · \(Int(record.progress*100))%"
    case .failed: return record.failure ?? "Download failed"
    case .completed: return "Ready to watch offline"
    }
  }
  private func play(_ record: OfflineDownload) {
    do {
      session.playback = DesktopPlayback(movie: record.movie, offline: try store.playback(record))
    } catch { self.error = error.localizedDescription }
  }
}
