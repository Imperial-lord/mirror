import AppKit
import SwiftUI

struct DesktopMovieView: View {
  let movieID: Int
  @Environment(\.dismiss) private var dismiss
  @Environment(DesktopSession.self) private var session
  @State private var model: MovieDetailViewModel
  @State private var save = false
  @State private var download = false
  @State private var allCredits = false
  init(movieID: Int) {
    self.movieID = movieID
    _model = State(initialValue: MovieDetailViewModel(movieId: movieID))
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 30) {
        DesktopIconButton(icon: .arrowLeft, help: "Back") { dismiss() }.padding(.top, 48)
        switch model.state {
        case .idle, .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 450)
        case .error(let message):
          DesktopError(message: message) { Task { await model.loadDetails() } }
        case .loaded(let movie, let suggestions):
          content(movie, suggestions: suggestions)
            .sheet(isPresented: $save) { DesktopSaveSheet(movie: movie) }
            .sheet(isPresented: $download) { DesktopDownloadSheet(movie: movie) }
        }
      }.padding(.horizontal, 38).padding(.bottom, 48)
    }.background(Color.mirrorBackground).task {
      if case .idle = model.state { await model.loadDetails() }
    }
  }
  private func content(_ movie: MovieDetail, suggestions: [Movie]) -> some View {
    VStack(alignment: .leading, spacing: 35) {
      ZStack(alignment: .bottomLeading) {
        DesktopImage(url: movie.backdropURL ?? movie.posterURL)
        LinearGradient(
          colors: [.black.opacity(0.2), .black.opacity(0.9)], startPoint: .center, endPoint: .bottom
        )
        HStack(alignment: .bottom, spacing: 25) {
          DesktopImage(url: movie.posterURL).frame(width: 145, height: 215).clipShape(
            RoundedRectangle(cornerRadius: 11))
          VStack(alignment: .leading, spacing: 15) {
            Text(movie.title).font(.system(size: 37, weight: .semibold)).tracking(-0.9).lineLimit(2)
            HStack(spacing: 13) {
              Text("IMDb \(movie.rating,specifier:"%.1f")").fontWeight(.semibold)
              Text(String(movie.year))
              Text(movie.formattedRuntime)
              if let language = movie.language { Text(language.uppercased()) }
            }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            Text((movie.genres ?? []).joined(separator: " · ")).font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 12) {
              Button {
                play(movie)
              } label: {
                HStack {
                  PhosphorView(.playBold, size: 18, color: .black)
                  Text("Play movie").fontWeight(.semibold)
                }.padding(.horizontal, 23).frame(height: 43).foregroundStyle(.black).background(
                  .white, in: Capsule())
              }.buttonStyle(.plain)
              Button {
                requireAccount { save = true }
              } label: {
                PhosphorView(
                  LibraryStore.shared.favorites.contains(where: { $0.id == movie.id })
                    ? .check : .add, size: 20, color: .white
                )
                .frame(width: 43, height: 43).background(.white.opacity(0.15), in: Circle())
              }.buttonStyle(.plain).help("Add to library")
              Button {
                requireAccount { download = true }
              } label: {
                PhosphorView(.downloadLinear, size: 20, color: .white).frame(width: 43, height: 43)
                  .background(
                    .white.opacity(0.15), in: Circle())
              }.buttonStyle(.plain).help("Download movie")
              if let url = URL(string: movie.url) {
                ShareLink(item: url) {
                  PhosphorView(.share, size: 20, color: .white).frame(width: 43, height: 43)
                    .background(
                      .white.opacity(0.15), in: Circle())
                }.buttonStyle(.plain).help("Share movie")
              }
            }.padding(.top, 7)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(32).foregroundStyle(.white)
      }.frame(height: 445).clipShape(RoundedRectangle(cornerRadius: 22))
      VStack(alignment: .leading, spacing: 14) {
        Text("About the movie").font(.system(size: 21, weight: .semibold))
        Text(movie.descriptionFull ?? movie.descriptionIntro ?? "No synopsis available.").font(
          .system(size: 14)
        ).lineSpacing(6).foregroundStyle(Color.mirrorTextSecondary).textSelection(.enabled)
        if let code = movie.ytTrailerCode, !code.isEmpty,
          let url = URL(string: "https://www.youtube.com/watch?v=\(code)")
        {
          DesktopAction(title: "Watch trailer", icon: .playLinear) { NSWorkspace.shared.open(url) }
            .padding(.top, 6)
        }
      }.frame(maxWidth: 850, alignment: .leading)
      if model.isLoadingCredits {
        ProgressView().frame(maxWidth: .infinity, minHeight: 100).accessibilityLabel(
          "Loading cast and crew")
      } else if !model.credits.isEmpty {
        VStack(alignment: .leading, spacing: 18) {
          HStack {
            Text("Cast & Crew").font(.system(size: 21, weight: .semibold))
            Spacer()
            Button(allCredits ? "Show less" : "View all") { allCredits.toggle() }.buttonStyle(
              .plain
            ).font(.caption).foregroundStyle(Color.mirrorTextSecondary)
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 210), spacing: 18)], alignment: .leading,
            spacing: 16
          ) {
            ForEach(allCredits ? model.credits : Array(model.credits.prefix(8))) { person in
              NavigationLink(value: DesktopRoute.person(person)) {
                HStack(spacing: 12) {
                  DesktopImage(url: person.avatarURL).frame(width: 52, height: 64).clipShape(
                    RoundedRectangle(cornerRadius: 10))
                  VStack(alignment: .leading, spacing: 5) {
                    Text(person.name).font(.system(size: 13, weight: .medium))
                    Text(person.characterName ?? person.creditRole).font(.system(size: 11))
                      .foregroundStyle(Color.mirrorTextTertiary).lineLimit(2)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(11).background(
                  Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 13))
              }.buttonStyle(.plain)
            }
          }
        }
      }
      if !movie.screenshots.isEmpty {
        VStack(alignment: .leading, spacing: 18) {
          Text("From the movie").font(.system(size: 21, weight: .semibold))
          HStack(spacing: 15) {
            ForEach(movie.screenshots, id: \.self) {
              DesktopImage(url: $0).aspectRatio(16 / 9, contentMode: .fit).clipShape(
                RoundedRectangle(cornerRadius: 12))
            }
          }
        }
      }
      if !suggestions.isEmpty { DesktopMovieRow(title: "You might also like", movies: suggestions) }
    }
  }
  private func requireAccount(_ action: () -> Void) {
    if AuthService.shared.isAuthenticated { action() } else { session.showSignIn = true }
  }
  private func play(_ movie: MovieDetail) {
    requireAccount { session.playback = DesktopPlayback(movie: movie) }
  }
}

struct DesktopSaveSheet: View {
  let movie: MovieDetail
  @Environment(\.dismiss) private var dismiss
  @State private var selection = LibrarySelection()
  @State private var newName = ""
  @State private var working = false
  @State private var message: String?
  @State private var initialized = false
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("Add to Library").font(.title2.weight(.semibold))
        Spacer()
        DesktopIconButton(icon: .close, help: "Close") { dismiss() }
      }
      Button {
        selection.toggleFavorite()
      } label: {
        row("Favorites", icon: .bookmarkLinear, selected: selection.favorite)
      }.buttonStyle(.plain)
      Text("My playlists").font(.headline)
      ScrollView {
        VStack(spacing: 9) {
          ForEach(LibraryStore.shared.playlists) { list in
            Button {
              selection.togglePlaylist(list.id)
            } label: {
              row(list.name, icon: .folder, selected: selection.playlists.contains(list.id))
            }.buttonStyle(.plain)
          }
        }
      }.frame(maxHeight: 230)
      HStack {
        TextField("New playlist name", text: $newName).desktopField()
        Button("Create") { create() }.disabled(
          newName.trimmingCharacters(in: .whitespaces).isEmpty || working)
      }
      if let message { Text(message).font(.caption).foregroundStyle(Color.mirrorRed) }
      HStack {
        Spacer()
        DesktopAction(title: "Cancel") { dismiss() }
        DesktopAction(title: "Add", primary: true) { save() }.disabled(
          working || !LibraryStore.shared.loaded)
      }
    }.padding(30).frame(width: 500).background(Color.mirrorBackground).foregroundStyle(
      Color.mirrorInk
    )
    .onAppear(perform: initialize).onChange(of: LibraryStore.shared.loaded) { _, _ in initialize() }
  }
  private func initialize() {
    guard !initialized, LibraryStore.shared.loaded else { return }
    let exists = LibraryStore.shared.favorites.contains { $0.id == movie.id }
    selection = LibrarySelection(
      favorite: exists || LibraryStore.shared.memberships(movieID: movie.id).isEmpty,
      playlists: LibraryStore.shared.memberships(movieID: movie.id))
    initialized = true
  }
  private func row(_ title: String, icon: PhosphorIcon, selected: Bool) -> some View {
    HStack {
      PhosphorView(icon, size: 22)
      Text(title)
      Spacer()
      DesktopSelectionMark(selected: selected)
    }.padding(17).background(Color.mirrorSurface2, in: RoundedRectangle(cornerRadius: 12))
  }
  private func save() {
    working = true
    Task {
      do {
        try await LibraryStore.shared.save(
          movie: SavedMovie(movie: movie), favorite: selection.favorite,
          selections: selection.playlists)
        dismiss()
      } catch { message = error.localizedDescription }
      working = false
    }
  }
  private func create() {
    working = true
    Task {
      do {
        let id = try await LibraryStore.shared.create(name: newName)
        selection.addPlaylist(id)
        newName = ""
      } catch { message = error.localizedDescription }
      working = false
    }
  }
}

struct DesktopDownloadSheet: View {
  let movie: MovieDetail
  @Environment(\.dismiss) private var dismiss
  @State private var quality = "1080p"
  @State private var languages: Set<String> = ["en"]
  @State private var message: String?
  private var choices: [Torrent] { MovieQuality.choices(movie.torrents ?? []) }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("Download movie").font(.title2.weight(.semibold))
        Spacer()
        DesktopIconButton(icon: .close, help: "Close") { dismiss() }
      }
      Text(movie.title).font(.headline)
      Text("Video quality").foregroundStyle(Color.mirrorTextSecondary)
      ForEach(choices) { torrent in
        Button {
          quality = torrent.quality
        } label: {
          HStack {
            Text(MovieQuality.label(torrent.quality))
            Spacer()
            Text(torrent.size).foregroundStyle(Color.mirrorTextTertiary)
            DesktopSelectionMark(selected: quality == torrent.quality)
          }.padding(13).background(Color.mirrorSurface2, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
      }
      Text("Subtitles").foregroundStyle(Color.mirrorTextSecondary)
      HStack(spacing: 9) {
        ForEach(SubtitleLanguage.codes, id: \.self) { code in
          Button {
            if languages.contains(code) { languages.remove(code) } else { languages.insert(code) }
          } label: {
            Text(SubtitleLanguage.name(code)).font(.system(size: 12)).padding(11).background(
              languages.contains(code) ? Color.mirrorSurface3 : .mirrorSurface1, in: Capsule()
            ).overlay(
              Capsule().stroke(Color.mirrorInk.opacity(languages.contains(code) ? 0.4 : 0.1)))
          }.buttonStyle(.plain)
        }
      }
      if DownloadStore.shared.records.contains(where: { $0.id == movie.id && $0.asset != nil }) {
        Text("Changing quality replaces the saved video. Existing subtitles are kept.").font(
          .caption
        ).foregroundStyle(Color.mirrorTextTertiary)
      }
      if let message { Text(message).font(.caption).foregroundStyle(Color.mirrorRed) }
      HStack {
        Spacer()
        DesktopAction(title: "Cancel") { dismiss() }
        DesktopAction(title: "Download", icon: .downloadLinear, primary: true) {
          guard let torrent = choices.first(where: { $0.quality == quality }) else { return }
          do {
            try DownloadStore.shared.enqueue(movie: movie, torrent: torrent, languages: languages)
            dismiss()
          } catch { message = error.localizedDescription }
        }.disabled(choices.isEmpty)
      }
    }.padding(30).frame(width: 520).background(Color.mirrorBackground).foregroundStyle(
      Color.mirrorInk
    )
    .onAppear {
      if !choices.contains(where: { $0.quality == quality }) {
        quality = choices.first?.quality ?? ""
      }
      if let record = DownloadStore.shared.records.first(where: { $0.id == movie.id }) {
        languages.formUnion(record.subtitles.keys)
      }
    }
  }
}

struct DesktopPersonView: View {
  let person: Cast
  @Environment(\.dismiss) private var dismiss
  @State private var biography: PersonBiography?
  @State private var movies: [Movie] = []
  @State private var loading = true
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 30) {
        DesktopIconButton(icon: .arrowLeft, help: "Back") { dismiss() }.padding(.top, 48)
        HStack(alignment: .top, spacing: 38) {
          if person.avatarURL != nil {
            DesktopImage(url: person.avatarURL).frame(width: 270, height: 350).clipShape(
              RoundedRectangle(cornerRadius: 20))
          }
          VStack(alignment: .leading, spacing: 18) {
            Text(person.name).font(.system(size: 38, weight: .semibold)).tracking(-1)
            Text(
              [person.creditRole, person.characterName].compactMap { $0 }.joined(separator: " · ")
            ).foregroundStyle(Color.mirrorTextSecondary)
            if loading { ProgressView() }
            if let biography {
              VStack(alignment: .leading, spacing: 14) {
                if let value = biography.birthName { detail("Birth name", value) }
                if let value = biography.birthDate { detail("Born", String(value.prefix(10))) }
                if let value = biography.birthPlace { detail("Birthplace", value) }
                if let entity = biography.entity {
                  Link("Biography source", destination: entity).font(.caption).foregroundStyle(
                    Color.mirrorTextSecondary)
                }
                if let source = biography.imageSource, person.avatarURL != nil {
                  Link("Photo credits and license", destination: source).font(.caption)
                    .foregroundStyle(Color.mirrorTextSecondary)
                }
              }.desktopPanel()
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
        }
        if !movies.isEmpty { DesktopMovieRow(title: "Filmography", movies: movies) }
      }.padding(.horizontal, 38).padding(.bottom, 45)
    }.background(Color.mirrorBackground).task {
      guard loading else { return }
      async let bio = PeopleMetadataService.shared.biography(person)
      async let films = PeopleMetadataService.shared.filmography(person)
      biography = try? await bio
      movies = (try? await films) ?? []
      loading = false
    }
  }
  private func detail(_ name: String, _ value: String) -> some View {
    HStack {
      Text(name).foregroundStyle(Color.mirrorTextTertiary)
      Spacer()
      Text(value).textSelection(.enabled)
    }.font(.callout)
  }
}
