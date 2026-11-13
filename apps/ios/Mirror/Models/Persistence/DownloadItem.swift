import Foundation
import SwiftData

@Model
public final class DownloadItem {
    @Attribute(.unique) public var torrentHash: String
    public var movieId: Int
    public var title: String
    public var posterURL: String?
    public var quality: String
    public var totalSize: Int
    public var downloadedSize: Int
    public var status: String // "queued", "downloading", "paused", "completed", "error"
    public var localFilePath: String?
    public var dateStarted: Date
    public var dateCompleted: Date?
    public var magnetURL: String

    public init(
        torrentHash: String,
        movieId: Int,
        title: String,
        posterURL: String?,
        quality: String,
        totalSize: Int,
        downloadedSize: Int = 0,
        status: String = "queued",
        localFilePath: String? = nil,
        dateStarted: Date = Date(),
        dateCompleted: Date? = nil,
        magnetURL: String
    ) {
        self.torrentHash = torrentHash
        self.movieId = movieId
        self.title = title
        self.posterURL = posterURL
        self.quality = quality
        self.totalSize = totalSize
        self.downloadedSize = downloadedSize
        self.status = status
        self.localFilePath = localFilePath
        self.dateStarted = dateStarted
        self.dateCompleted = dateCompleted
        self.magnetURL = magnetURL
    }

    public var progress: Double {
        guard totalSize > 0 else { return 0 }
        return Double(downloadedSize) / Double(totalSize)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}
