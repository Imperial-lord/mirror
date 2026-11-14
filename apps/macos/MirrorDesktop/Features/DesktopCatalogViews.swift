import SwiftData
import SwiftUI

struct DesktopPoster: View {
  let movie: Movie
  @Environment(DesktopSession.self) private var session
  @State private var hovering = false
  var body: some View {
    Button {
      session.open(movie.id)
    } label: {
      VStack(alignment: .leading, spacing: 9) {
        DesktopImage(url: movie.posterURL).aspectRatio(0.675, contentMode: .fit)
          .overlay(alignment: .bottomTrailing) {
            if hovering {
              PhosphorView(.playBold, size: 18, color: .black).frame(width: 38, height: 38)
                .background(.white, in: Circle()).padding(12)
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 13))
          .overlay(
            RoundedRectangle(cornerRadius: 13).stroke(
              Color.mirrorInk.opacity(hovering ? 0.45 : 0.07)))
        Text(movie.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
        Text("\(String(movie.year)) · \(movie.genres?.first ?? "Movie")").font(.system(size: 11))
          .foregroundStyle(Color.mirrorTextTertiary).lineLimit(1)
      }.contentShape(Rectangle())
    }.buttonStyle(.plain).onHover { hovering = $0 }.animation(
      .easeOut(duration: 0.16), value: hovering
    )
    .contextMenu {
      Button("View movie") { session.open(movie.id) }
      Button("Play movie") { session.play(movie.id) }
    }
  }
}

struct DesktopMovieRow: View {
  let title: String
  let movies: [Movie]
  @Environment(DesktopSession.self) private var session
  var body: some View {
    VStack(alignment: .leading, spacing: 19) {
      HStack {
        Text(title).font(.system(size: 21, weight: .semibold)).tracking(-0.4)
        Spacer()
        Button {
          session.path.append(DesktopRoute.collection(title, movies.map(\.id)))
        } label: {
          HStack(spacing: 5) {
            Text("View all").font(.system(size: 11))
            PhosphorView(.caretRight, size: 11)
          }.foregroundStyle(Color.mirrorTextSecondary)
        }.buttonStyle(.plain)
      }
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 18) {
          ForEach(movies) { DesktopPoster(movie: $0).frame(width: 157) }
        }.padding(.bottom, 3)
      }.scrollIndicators(.hidden)
    }
  }
}

struct DesktopHomeView: View {
  @Environment(DesktopSession.self) private var session
  @Environment(\.modelContext) private var context
  @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var history:
    [WatchHistoryItem]
  @State private var model = HomeViewModel()
  @State private var heroIndex = 0
  private var userHistory: [WatchHistoryItem] {
    history.filter { $0.userId == AuthService.shared.currentUser?.uid }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 38) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 5) {
            Text("A good day for a great movie.").font(.system(size: 27, weight: .semibold))
              .tracking(-0.7)
            Text("Find a story worth getting lost in.").font(.system(size: 12)).foregroundStyle(
              Color.mirrorTextSecondary)
          }
          Spacer()
          DesktopIconButton(icon: .searchLinear, help: "Search movies · ⌘F") {
            session.navigate(.catalog)
          }
        }.padding(.top, 44)
        if model.isLoading {
          ProgressView().frame(maxWidth: .infinity, minHeight: 380)
        } else if let error = model.errorMessage {
          DesktopError(message: error) { Task { await model.loadAll() } }
        } else if !model.heroMovies.isEmpty {
          hero(model.heroMovies[heroIndex % model.heroMovies.count])
        }
        if !userHistory.filter(\.isInProgress).isEmpty {
          DesktopContinueRow(items: Array(userHistory.filter(\.isInProgress).prefix(10)))
        }
        if !model.selectedForYou.isEmpty {
          DesktopMovieRow(title: "Selected For You", movies: model.selectedForYou)
        }
        if !model.trendingMovies.isEmpty {
          DesktopMovieRow(title: "Popular Now", movies: model.trendingMovies)
        }
        if !model.topRated.isEmpty { DesktopMovieRow(title: "Top Rated", movies: model.topRated) }
        ForEach(Genre.catalogGenres) { genre in
          Group {
            if let movies = model.genreMovies[genre], !movies.isEmpty {
              DesktopMovieRow(title: genre.bestTitle, movies: movies)
            } else if model.genreErrors[genre] != nil {
              HStack {
                Text(genre.bestTitle).font(.headline)
                Spacer()
                Button("Retry") { Task { await model.loadGenre(genre, retry: true) } }
              }
            } else {
              ProgressView().frame(maxWidth: .infinity, minHeight: 40)
            }
          }.task(id: model.collectionRevision) { await model.loadGenre(genre) }
        }
      }.padding(.horizontal, 38).padding(.bottom, 45)
    }.scrollIndicators(.hidden).background(Color.mirrorBackground)
      .task {
        if model.heroMovies.isEmpty { await model.loadAll() }
        await model.personalize(history: userHistory.map(WatchPreference.init))
      }
      .task(
        id: userHistory.map { "\($0.movieId)-\($0.lastWatched.timeIntervalSince1970)" }.joined()
      ) {
        if !model.isLoading {
          await model.personalize(history: userHistory.map(WatchPreference.init))
        }
      }
  }
  private func hero(_ movie: Movie) -> some View {
    ZStack(alignment: .bottomLeading) {
      DesktopImage(url: movie.backdropURL ?? movie.posterURL)
      LinearGradient(
        colors: [.black.opacity(0.85), .black.opacity(0.25), .clear], startPoint: .leading,
        endPoint: .trailing)
      LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
      VStack(alignment: .leading, spacing: 17) {
        Text("IN THE SPOTLIGHT").font(.system(size: 10, weight: .semibold)).tracking(2.5)
          .foregroundStyle(.white.opacity(0.7))
        Text(movie.title).font(.system(size: 40, weight: .semibold)).tracking(-1.2).lineLimit(2)
          .frame(maxWidth: 500, alignment: .leading)
        HStack(spacing: 12) {
          Text("IMDb \(movie.rating,specifier:"%.1f")").fontWeight(.semibold)
          Text(String(movie.year))
          Text(movie.formattedRuntime)
          Text(movie.genres?.first ?? "Movie")
        }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
        if let summary = movie.summary, !summary.isEmpty {
          Text(summary).font(.system(size: 13)).lineSpacing(4).lineLimit(2).foregroundStyle(
            .white.opacity(0.65)
          ).frame(maxWidth: 450, alignment: .leading)
        }
        HStack(spacing: 12) {
          Button {
            session.play(movie.id)
          } label: {
            HStack {
              PhosphorView(.playBold, size: 18, color: .black)
              Text("Watch now").fontWeight(.semibold)
            }
            .padding(.horizontal, 24).frame(height: 44).foregroundStyle(.black).background(
              .white, in: Capsule())
          }.buttonStyle(.plain)
          Button {
            session.open(movie.id)
          } label: {
            HStack {
              PhosphorView(.infoLinear, size: 18, color: .white)
              Text("More info")
            }.font(.system(size: 13)).padding(.horizontal, 20).frame(height: 44).background(
              .white.opacity(0.13), in: Capsule())
          }.buttonStyle(.plain)
        }.padding(.top, 4)
      }.padding(35).foregroundStyle(.white)
    }.frame(height: 440).clipShape(RoundedRectangle(cornerRadius: 22))
      .overlay(alignment: .bottomTrailing) {
        HStack(spacing: 8) {
          ForEach(model.heroMovies.indices, id: \.self) { index in
            Button {
              withAnimation { heroIndex = index }
            } label: {
              Capsule().fill(.white.opacity(index == heroIndex ? 1 : 0.35)).frame(
                width: index == heroIndex ? 23 : 6, height: 6)
            }.buttonStyle(.plain).help("Featured movie \(index+1)")
          }
        }.padding(26)
      }
  }
}

struct DesktopContinueRow: View {
  let items: [WatchHistoryItem]
  @Environment(DesktopSession.self) private var session
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Continue Watching").font(.system(size: 21, weight: .semibold))
        Spacer()
        Button("View all") { session.navigate(.library) }.buttonStyle(.plain).font(.caption)
          .foregroundStyle(Color.mirrorTextSecondary)
      }
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 18) {
          ForEach(items) { item in
            Button {
              session.play(item.movieId)
            } label: {
              VStack(alignment: .leading, spacing: 9) {
                DesktopImage(url: URL(string: item.backdropURL ?? item.posterURL ?? ""))
                  .frame(height: 145).overlay {
                    PhosphorView(.playBold, size: 18, color: .white).frame(width: 43, height: 43)
                      .background(.black.opacity(0.6), in: Circle())
                  }.overlay(alignment: .bottomLeading) {
                    GeometryReader { proxy in
                      Rectangle().fill(.white).frame(
                        width: proxy.size.width * item.progressPercentage, height: 3)
                    }.frame(height: 3)
                  }.overlay(alignment: .bottomTrailing) {
                    Text(item.remainingTime).font(.system(size: 10, weight: .medium))
                      .foregroundStyle(.white).padding(6).background(
                        .black.opacity(0.65), in: Capsule()
                      ).padding(9)
                  }.clipShape(RoundedRectangle(cornerRadius: 12))
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(
                  Color.mirrorTextTertiary)
              }.frame(width: 260)
            }.buttonStyle(.plain)
          }
        }
      }.scrollIndicators(.hidden)
    }
  }
}

struct DesktopCatalogView: View {
  @State private var model = SearchViewModel()
  @State private var filters = false
  @FocusState private var searchFocused: Bool
  var body: some View {
    @Bindable var model = model
    ScrollView {
      VStack(alignment: .leading, spacing: 25) {
        DesktopPageHeader(title: "Catalog", subtitle: "Your next obsession is one search away.")
        HStack(spacing: 12) {
          HStack(spacing: 12) {
            PhosphorView(.searchLinear, size: 20, color: .mirrorTextSecondary)
            TextField("Search movies", text: $model.query).textFieldStyle(.plain).focused(
              $searchFocused
            ).onSubmit { Task { await model.performSearch() } }
            if !model.query.isEmpty {
              Button {
                model.query = ""
              } label: {
                PhosphorView(.closeCircle, size: 16)
              }.buttonStyle(.plain)
            }
          }.padding(16).background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 13))
          DesktopIconButton(icon: .filter, help: "Show filters") {
            withAnimation { filters.toggle() }
          }
        }
        if filters { filterPanel }
        ScrollView(.horizontal) {
          HStack(spacing: 9) {
            ForEach(Genre.allCases) { genre in
              let selected = (model.selectedGenre ?? "All") == genre.rawValue
              Button {
                model.selectedGenre = genre == .all ? nil : genre.rawValue
                Task { await model.performSearch() }
              } label: {
                Text(genre.rawValue).font(
                  .system(size: 12, weight: selected ? .semibold : .regular)
                ).padding(.horizontal, 18).padding(.vertical, 10)
                  .background(selected ? Color.mirrorSurface3 : .mirrorSurface1, in: Capsule())
                  .overlay(Capsule().stroke(Color.mirrorInk.opacity(selected ? 0.3 : 0.07)))
              }.buttonStyle(.plain)
            }
          }
        }.scrollIndicators(.hidden)
        if let error = model.errorMessage {
          DesktopError(message: error) { Task { await model.performSearch() } }
        }
        if model.isEmpty {
          DesktopEmpty(
            title: "We couldn’t find anything",
            message: "Try another title or adjust your filters.", icon: .searchLinear)
        }
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 22)],
          alignment: .leading, spacing: 30
        ) {
          ForEach(model.searchResults) { DesktopPoster(movie: $0) }
        }
        if model.isSearching {
          ProgressView().frame(maxWidth: .infinity, minHeight: 70)
        } else if model.canLoadMore {
          DesktopAction(title: "Load more movies") { Task { await model.loadNextPage() } }.frame(
            maxWidth: .infinity)
        }
      }.padding(38).padding(.top, 14)
    }.background(Color.mirrorBackground).task {
      searchFocused = true
      if !model.hasSearched { await model.loadIdleCatalog() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .mirrorFocusSearch)) { _ in
      searchFocused = true
    }
  }
  private var filterPanel: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 20) {
        filterPicker(
          "Year",
          selection: Binding(
            get: { model.selectedYear ?? 0 }, set: { model.selectedYear = $0 == 0 ? nil : $0 })
        ) {
          Text("All years").tag(0)
          ForEach(
            Array((1900...Calendar.current.component(.year, from: Date())).reversed()), id: \.self
          ) { Text(String($0)).tag($0) }
        }
        filterPicker(
          "Country",
          selection: Binding(
            get: { model.selectedCountry ?? "" },
            set: { model.selectedCountry = $0.isEmpty ? nil : $0 })
        ) {
          Text("All countries").tag("")
          ForEach(CatalogFilterOption.countries) { Text($0.name).tag($0.id) }
        }
        filterPicker(
          "Studio",
          selection: Binding(
            get: { model.selectedStudio ?? "" },
            set: { model.selectedStudio = $0.isEmpty ? nil : $0 })
        ) {
          Text("All studios").tag("")
          ForEach(CatalogFilterOption.studios) { Text($0.name).tag($0.id) }
        }
      }
      HStack(spacing: 20) {
        filterPicker(
          "Minimum rating",
          selection: Binding(get: { model.minimumRating }, set: { model.minimumRating = $0 })
        ) {
          Text("Any rating").tag(0)
          ForEach(1...9, id: \.self) { Text("\($0)+").tag($0) }
        }
        filterPicker(
          "Sort by", selection: Binding(get: { model.sortBy }, set: { model.sortBy = $0 })
        ) {
          Text("Popular").tag("like_count")
          Text("Newest").tag("date_added")
          Text("Rating").tag("rating")
          Text("Release year").tag("year")
        }
        Spacer()
        DesktopAction(title: "Reset") {
          model.selectedCountry = nil
          model.selectedStudio = nil
          model.selectedYear = nil
          model.minimumRating = 0
          model.sortBy = "like_count"
          model.selectedGenre = nil
          Task { await model.performSearch() }
        }
        DesktopAction(title: "Apply", primary: true) { Task { await model.performSearch() } }
      }
    }.desktopPanel()
  }
  private func filterPicker<Value: Hashable, Content: View>(
    _ title: String, selection: Binding<Value>, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.caption).foregroundStyle(Color.mirrorTextTertiary)
      Picker(title, selection: selection, content: content).labelsHidden().frame(
        maxWidth: .infinity
      ).pickerStyle(.menu)
    }
  }
}

extension MovieDetail {
  var catalogMovie: Movie? {
    (try? JSONEncoder().encode(self)).flatMap { try? JSONDecoder().decode(Movie.self, from: $0) }
  }
}
struct DesktopCollectionView: View {
  let title: String
  let ids: [Int]
  @State private var movies: [Movie] = []
  @State private var loading = true
  @State private var failure = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        DesktopIconButton(icon: .arrowLeft, help: "Back") { dismiss() }
        DesktopPageHeader(title: title)
        if loading {
          ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        } else if failure {
          DesktopError(message: "Couldn’t load these movies.") { Task { await load() } }
        } else if movies.isEmpty {
          DesktopEmpty(
            title: "Nothing here yet", message: "Movies will appear here when you add them.")
        }
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 22)], spacing: 28
        ) { ForEach(movies) { DesktopPoster(movie: $0) } }
      }.padding(38).padding(.top, 14)
    }.background(Color.mirrorBackground).task { await load() }
  }
  private func load() async {
    loading = true
    failure = false
    var result: [Int: Movie] = [:]
    for batch in stride(from: 0, to: ids.count, by: 4) {
      await withTaskGroup(of: Movie?.self) { group in
        for id in ids[batch..<min(batch + 4, ids.count)] {
          group.addTask {
            (try? await MovieRepository.shared.fetchMovieDetail(id: id))?.catalogMovie
          }
        }
        for await movie in group { if let movie { result[movie.id] = movie } }
      }
    }
    movies = ids.compactMap { result[$0] }
    failure = !ids.isEmpty && result.isEmpty
    loading = false
  }
}
