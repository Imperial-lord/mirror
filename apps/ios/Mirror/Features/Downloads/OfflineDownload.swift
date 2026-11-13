import Foundation

struct OfflineDownload: Codable, Identifiable {
    var id: Int { movie.id }
    var movie: MovieDetail
    var torrent: Torrent
    var generation: UUID = UUID()
    var status: Status = .queued
    var bytes: Int64 = 0
    var total: Int64 = 0
    var partialFile = UUID().uuidString + ".part"
    var asset: Asset?
    var subtitles: [String: String] = [:]
    var requestedSubtitles: Set<String> = []
    var subtitleRequestsFinished: Set<String> = []
    var notices: [String] = []
    var failure: String?
    var position: Double = 0
    var duration: Double = 0
    var lastPlayedAt: Date?
    var updatedAt = Date()
    var streamURL: URL?
    var posterFile: String?

    enum Status: String, Codable { case queued, preparing, downloading, paused, failed, completed }
    struct Asset: Codable {
        let file: String
        let quality: String
        let hash: String
        let size: Int64
    }
    var needsVideo: Bool { asset?.hash != torrent.hash }
    var progress: Double { total > 0 ? min(1, max(0, Double(bytes) / Double(total))) : 0 }
    var quality: String { MovieQuality.label(torrent.quality) }
    var size: String { total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : torrent.size }
}

struct OfflineMovie: Identifiable {
    var id: Int { movie.id }
    let movie: MovieDetail
    let file: URL
    let quality: String
    let subtitles: [String: URL]
    let position: Double
    let lastPlayedAt: Date?
}

enum MovieQuality {
    static let supported = ["2160p", "1080p", "720p", "480p"]
    static func label(_ quality: String) -> String {
        switch quality {
        case "2160p": return "4K 2160"
        case "1080p": return "Full HD 1080"
        case "720p": return "HD 720"
        case "480p": return "SD 480"
        default: return quality
        }
    }
    static func choices(_ torrents: [Torrent]) -> [Torrent] {
        supported.compactMap { quality in
            torrents.filter { $0.quality == quality }.sorted { $0.seeds > $1.seeds }.first
        }
    }
}

enum SubtitleLanguage {
    static let codes = ["en", "it", "es", "fr"]
    static func name(_ code: String) -> String {
        ["en": "English", "it": "Italian", "es": "Spanish", "fr": "French"][code] ?? code
    }
    static func code(_ name: String) -> String? { codes.first { self.name($0) == name } }
}

// HTTP byte offsets and lengths are checked before appending anything to a saved movie.
enum DownloadRange {
    static let chunkSize: Int64 = 16 * 1024 * 1024
    static func end(offset: Int64, total: Int64) -> Int64 { min(total - 1, offset + chunkSize - 1) }
    static func valid(header: String?, offset: Int64, end: Int64, total: Int64, size: Int64) -> Bool {
        header == "bytes \(offset)-\(end)/\(total)" && size == end - offset + 1 && offset >= 0 && end < total
    }
    static func append(chunk: URL, to partial: URL, offset: Int64) throws {
        guard offset >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        let fm = FileManager.default
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        let output = try FileHandle(forWritingTo: partial)
        defer { try? output.close() }
        let existing = try output.seekToEnd()
        guard existing >= UInt64(offset) else { throw CocoaError(.fileReadCorruptFile) }
        // A crash between an append and a manifest write must never duplicate a chunk.
        try output.truncate(atOffset: UInt64(offset)); try output.seek(toOffset: UInt64(offset))
        let input = try FileHandle(forReadingFrom: chunk)
        defer { try? input.close() }
        while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
        try output.synchronize()
    }
}
