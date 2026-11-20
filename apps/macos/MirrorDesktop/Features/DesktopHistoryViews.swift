import SwiftData
import SwiftUI

struct DesktopHistoryContinueCard: View {
  let item: WatchHistoryItem
  @Environment(DesktopSession.self) private var session
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button {
        session.play(item.movieId)
      } label: {
        artwork
      }.buttonStyle(.plain)
        .accessibilityLabel("Continue watching \(item.title)")
      HStack(spacing: 4) {
        Button {
          session.play(item.movieId)
        } label: {
          Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
        WatchHistoryMenu(
          movieId: item.movieId, title: item.title, userId: item.userId,
          watched: false, onInformation: { session.open(item.movieId) })
      }
      Text(item.subtitle).font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary)
    }
  }
  private var artwork: some View {
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
          .foregroundStyle(.white).padding(6).background(.black.opacity(0.65), in: Capsule())
          .padding(9)
      }.clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

struct DesktopHistoryPoster: View {
  let item: WatchHistoryItem
  @Environment(DesktopSession.self) private var session
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button {
        session.open(item.movieId)
      } label: {
        DesktopImage(url: URL(string: item.posterURL ?? "")).aspectRatio(0.675, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 13))
      }.buttonStyle(.plain).accessibilityLabel(item.title)
      HStack(spacing: 4) {
        Button {
          session.open(item.movieId)
        } label: {
          Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
        WatchHistoryMenu(
          movieId: item.movieId, title: item.title, userId: item.userId, watched: true)
      }
      Text(item.subtitle).font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary)
    }
  }
}

struct DesktopHistoryCollectionView: View {
  let collection: HistoryCollection
  @Environment(DesktopSession.self) private var session
  @Environment(\.modelContext) private var context
  @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var history:
    [WatchHistoryItem]
  @State private var error: String?
  private var title: String {
    if case .genre(let name) = collection { return "Watched · \(name)" }
    return collection.title
  }
  private var movies: [WatchHistoryItem] {
    LibraryHistory.movies(
      in: collection, from: history.filter { $0.userId == AuthService.shared.currentUser?.uid })
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        DesktopIconButton(icon: .arrowLeft, help: "Back") { session.goBack() }
        DesktopPageHeader(title: title)
        if let error { Text(error).font(.callout).foregroundStyle(Color.mirrorTextSecondary) }
        if movies.isEmpty {
          DesktopEmpty(title: "Nothing here yet", message: "Movies you watch will appear here.")
        } else if collection == .continuing {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 22)], spacing: 28
          ) {
            ForEach(movies) { DesktopHistoryContinueCard(item: $0) }
          }
        } else {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 22)], spacing: 28
          ) {
            ForEach(movies) { DesktopHistoryPoster(item: $0) }
          }
        }
      }.padding(38).padding(.top, 14)
    }.background(Color.mirrorBackground)
      .task { error = await WatchHistorySync.sync(context: context) }
  }
}
