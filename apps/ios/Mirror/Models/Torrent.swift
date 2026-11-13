import Foundation

public struct Torrent: Codable, Identifiable, Hashable {
    public let url: String
    public let hash: String
    public let quality: String
    public let type: String
    public let isRepack: String?
    public let videoCodec: String?
    public let bitDepth: String?
    public let audioChannels: String?
    public let seeds: Int
    public let peers: Int
    public let size: String
    public let sizeBytes: Int
    public let dateUploaded: String
    public let dateUploadedUnix: Int?

    public var id: String { hash }

    public var magnetURL: String {
        let trackers = [
            "udp://open.demonii.com:1337/announce",
            "udp://tracker.openbittorrent.com:80",
            "udp://tracker.coppersurfer.tk:6969",
            "udp://glotorrents.pw:6969/announce",
            "udp://tracker.opentrackr.org:1337/announce"
        ].map { "&tr=\($0)" }.joined()

        let encodedName = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "magnet:?xt=urn:btih:\(hash)&dn=\(encodedName)\(trackers)"
    }

    enum CodingKeys: String, CodingKey {
        case url
        case hash
        case quality
        case type
        case isRepack = "is_repack"
        case videoCodec = "video_codec"
        case bitDepth = "bit_depth"
        case audioChannels = "audio_channels"
        case seeds
        case peers
        case size
        case sizeBytes = "size_bytes"
        case dateUploaded = "date_uploaded"
        case dateUploadedUnix = "date_uploaded_unix"
    }
}
