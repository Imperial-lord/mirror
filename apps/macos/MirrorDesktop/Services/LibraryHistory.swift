import Foundation

enum HistoryCollection: Hashable {
  case continuing, watched, genres
  case genre(String)
  var title: String {
    switch self {
    case .continuing: return "Continue Watching"
    case .watched: return "Watched"
    case .genres: return "Genres you Watched"
    case .genre(let name): return name
    }
  }
}

enum LibraryHistory {
  static func genres(in items: [WatchHistoryItem]) -> [String] {
    var counts: [String: Int] = [:]
    for item in items where item.isWatched {
      for genre in Set(item.genres) where genre != "All" { counts[genre, default: 0] += 1 }
    }
    return counts.keys.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0]! > counts[$1]! }
  }
  static func movies(in collection: HistoryCollection, from items: [WatchHistoryItem])
    -> [WatchHistoryItem]
  {
    let sorted = items.sorted { $0.lastWatched > $1.lastWatched }
    switch collection {
    case .continuing: return sorted.filter(\.isInProgress)
    case .watched, .genres: return sorted.filter(\.isWatched)
    case .genre(let name): return sorted.filter { $0.isWatched && $0.genres.contains(name) }
    }
  }
}
