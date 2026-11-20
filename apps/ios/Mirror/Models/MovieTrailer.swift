import Foundation

struct MovieTrailer: Identifiable, Equatable {
  let id: String
  let title: String
  init?(code: String?, title: String) {
    guard let code, code.utf8.count == 11,
      code.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 95
      })
    else { return nil }
    id = code
    self.title = title
  }
}

extension MovieDetail {
  var trailer: MovieTrailer? { MovieTrailer(code: ytTrailerCode, title: title) }
}
