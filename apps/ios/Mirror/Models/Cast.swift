import Foundation

public struct Cast: Codable, Identifiable, Hashable {
    public let name: String
    public let characterName: String?
    public let urlSmallImage: String?
    public let imdbCode: String?
    public var department: String? = nil
    public var entityID: String? = nil

    public var creditRole: String { department ?? "Actor" }
    public var normalizedIMDbID: String? {
        guard let code = imdbCode else { return nil }
        let value = code.hasPrefix("nm") ? code : "nm" + code
        return value.range(of: "^nm[0-9]{5,12}$", options: .regularExpression) == nil ? nil : value
    }

    public var id: String { (normalizedIMDbID ?? entityID ?? name) + "|" + creditRole }

    public var avatarURL: URL? {
        guard let urlString = urlSmallImage, !urlString.isEmpty else { return nil }
        var normalized = urlString.replacingOccurrences(of: "https://yts.mx/", with: "https://img.yts.gg/")
        normalized = normalized.replacingOccurrences(of: "https://yts.gg/", with: "https://img.yts.gg/")
        normalized = normalized.replacingOccurrences(of: "http://", with: "https://")
        return URL(string: normalized)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case characterName = "character_name"
        case urlSmallImage = "url_small_image"
        case imdbCode = "imdb_code"
        case department
        case entityID = "entity_id"
    }
}
