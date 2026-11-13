import Foundation

public enum Genre: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case action = "Action"
    case adventure = "Adventure"
    case animation = "Animation"
    case comedy = "Comedy"
    case crime = "Crime"
    case documentary = "Documentary"
    case drama = "Drama"
    case family = "Family"
    case fantasy = "Fantasy"
    case history = "History"
    case music = "Music"
    case horror = "Horror"
    case mystery = "Mystery"
    case romance = "Romance"
    case sciFi = "Sci-Fi"
    case thriller = "Thriller"
    case war = "War"
    case western = "Western"

    public static var catalogGenres: [Genre] { allCases.filter { $0 != .all } }
    public var bestTitle: String {
        switch self {
        case .thriller: return "Best Thrillers"
        case .horror: return "Best Horrors"
        default: return "Best \(rawValue)"
        }
    }
    public var id: String { rawValue }
}
