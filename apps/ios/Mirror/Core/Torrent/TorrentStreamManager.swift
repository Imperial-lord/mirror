import Foundation
import SwiftTorrent

public enum TorrentPlaybackState: Equatable {
    case idle
    case connecting(seeds: Int)
    case buffering(progress: Double, speed: String, seeds: Int)
    case ready(streamURL: URL)
    case playing(speed: String, seeds: Int, progress: Double)
    case paused
    case completed
    case error(String)
}

final class CompletedPiecesTracker: @unchecked Sendable {
    private var completed = Set<Int>()
    private let lock = NSLock()

    func markPieceCompleted(_ index: Int) {
        lock.lock()
        completed.insert(index)
        lock.unlock()
    }

    func isPieceReady(_ index: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed.contains(index)
    }
}

@MainActor
@Observable
public final class TorrentStreamManager {
    public static let shared = TorrentStreamManager()

    public var state: TorrentPlaybackState = .idle
    public var currentTorrent: Torrent?
    public var currentMovie: MovieDetail?
    public var downloadSpeed: String = "0 KB/s"
    public var seedsCount: Int = 0
    public var progress: Double = 0.0
    public var streamURL: URL?

    private var activeTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var torrentSession: Session?
    private var currentHandle: TorrentHandle?
    private let inAppServer = MirrorInAppStreamServer()

    public init() {}

    public func startStream(movie: MovieDetail, quality: String = "1080p", onReady: (@MainActor @Sendable (URL) -> Void)? = nil) {
        stopStream()
        currentMovie = movie

        let requested = quality.contains("1080") ? "1080p" : quality.contains("720") ? "720p" : quality.contains("2160") ? "2160p" : quality
        let torrents = (movie.torrents ?? []).filter { $0.hash.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil }
        guard let torrent = torrents.sorted(by: { lhs, rhs in
            if (lhs.quality == requested) != (rhs.quality == requested) { return lhs.quality == requested }
            return lhs.seeds > rhs.seeds
        }).first else {
            state = .error("No playable torrent is available for this movie.")
            return
        }

        currentTorrent = torrent
        seedsCount = torrent.seeds
        state = .connecting(seeds: seedsCount)

        let piecesTracker = CompletedPiecesTracker()
        activeTask = Task {
            do {
                let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Torrents")
                    .appendingPathComponent(torrent.hash.uppercased())
                try? FileManager.default.createDirectory(at: cacheBase, withIntermediateDirectories: true)

                // 1. Fetch .torrent file with strict short timeout
                var torrentData: Data? = nil
                let mirrors = [
                    torrent.url,
                    "https://yts.gg/torrent/download/\(torrent.hash.uppercased())",
                    "https://yts.mx/torrent/download/\(torrent.hash.uppercased())"
                ]

                let sessionConfig = URLSessionConfiguration.ephemeral
                sessionConfig.timeoutIntervalForRequest = 4.0
                sessionConfig.timeoutIntervalForResource = 6.0
                let downloadSession = URLSession(configuration: sessionConfig)

                for mirrorStr in mirrors {
                    guard let mirrorURL = URL(string: mirrorStr) else { continue }
                    var req = URLRequest(url: mirrorURL)
                    req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                    if let (data, resp) = try? await downloadSession.data(for: req),
                       let http = resp as? HTTPURLResponse, http.statusCode == 200,
                       data.count > 80, data.first == 0x64 { // 'd' in bencode
                        torrentData = data
                        print("[TorrentStreamManager] Acquired .torrent file directly from \(mirrorStr)")
                        break
                    }
                }

                try Task.checkCancellation()
                // 2. Initialize in-app SwiftTorrent Session
                let session = Session(settings: SessionSettings(
                    listenPort: 6881,
                    dhtEnabled: true,
                    savePath: cacheBase.path
                ))
                self.torrentSession = session

                let handle: TorrentHandle
                if let data = torrentData {
                    let tempTorrentPath = cacheBase.appendingPathComponent("meta.torrent")
                    try data.write(to: tempTorrentPath)
                    var params = try AddTorrentParams.fromFile(tempTorrentPath.path, savePath: cacheBase.path)
                    params.paused = true
                    handle = try await session.addTorrent(params)
                } else {
                    let tr = [
                        "udp://tracker.opentrackr.org:1337/announce",
                        "udp://open.demonii.com:1337/announce",
                        "udp://tracker.openbittorrent.com:80",
                        "udp://open.stealth.si:80/announce",
                        "udp://tracker.torrent.eu.org:451/announce"
                    ].map { "&tr=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined()
                    let magnet = "magnet:?xt=urn:btih:\(torrent.hash)\(tr)"
                    var params = try AddTorrentParams.fromMagnet(magnet, savePath: cacheBase.path)
                    params.paused = true
                    handle = try await session.addTorrent(params)
                }

                try Task.checkCancellation()
                self.currentHandle = handle
                await handle.setOnPieceCompleted { pieceIdx in
                    piecesTracker.markPieceCompleted(pieceIdx)
                }
                try await handle.start()
                try Task.checkCancellation()

                // 3. Wait for metadata
                let info = try await handle.waitForMetadata(timeout: 30)
                try Task.checkCancellation()

                // 4. Find the main video file
                guard let videoFile = info.files
                    .filter({ f in
                        let lower = f.path.lowercased()
                        return lower.hasSuffix(".mp4") || lower.hasSuffix(".m4v") || lower.hasSuffix(".mov")
                    })
                    .max(by: { $0.length < $1.length }) else {
                    throw NSError(domain: "TorrentStreamManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No compatible MP4 video found in this torrent. Try another quality."])
                }

                let videoPath = cacheBase.appendingPathComponent(videoFile.path)

                // 5. Start in-app HTTP streaming server (100% on-device)
                let localStreamURL = try await self.inAppServer.start(
                    videoFileURL: videoPath,
                    expectedSize: videoFile.length,
                    pieceLength: info.pieceLength,
                    fileOffsetInTorrent: videoFile.offset,
                    isPieceReady: { pieceIdx in piecesTracker.isPieceReady(pieceIdx) }
                )

                try Task.checkCancellation()
                self.inAppServer.onReadRequested = { start, end in
                    let first = Int((videoFile.offset + start) / Int64(info.pieceLength))
                    let last = Int((videoFile.offset + end) / Int64(info.pieceLength))
                    // Prioritize a bounded window at AVPlayer's requested offset, including moov seeks.
                    let indices = Array(first...min(last, first + 15))
                    Task { await handle.prioritizePieces(indices) }
                }

                // 6. Buffer check: wait for Piece 0 so AVPlayer has valid container headers
                self.state = .buffering(progress: 0.01, speed: self.downloadSpeed, seeds: self.seedsCount)
                let startTime = Date()
                var isReady = false
                while Date().timeIntervalSince(startTime) < 30.0 {
                    let status = await handle.status()
                    self.seedsCount = status.numPeers
                    self.downloadSpeed = Self.formatSpeed(status.downloadRate)
                    self.progress = status.progress
                    self.state = .buffering(progress: max(0.02, status.progress), speed: self.downloadSpeed, seeds: self.seedsCount)

                    try Task.checkCancellation()
                    let firstVideoPiece = Int(videoFile.offset / Int64(info.pieceLength))
                    if piecesTracker.isPieceReady(firstVideoPiece) {
                        isReady = true
                        break
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }

                guard isReady else {
                    throw NSError(domain: "TorrentStreamManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Torrent swarm is slow to connect. Please try another quality or movie."])
                }

                try Task.checkCancellation()

                self.streamURL = localStreamURL
                self.state = .ready(streamURL: localStreamURL)
                onReady?(localStreamURL)

                self.startMonitoring(handle: handle)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .error("Streaming error: \(error.localizedDescription)")
            }
        }
    }

    private func startMonitoring(handle: TorrentHandle) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self, !Task.isCancelled else { break }
                let status = await handle.status()
                await MainActor.run {
                    self.seedsCount = status.numPeers
                    self.downloadSpeed = Self.formatSpeed(status.downloadRate)
                    self.progress = status.progress

                    if case .ready = self.state {
                        self.state = .playing(speed: self.downloadSpeed, seeds: self.seedsCount, progress: self.progress)
                    } else if case .playing = self.state {
                        self.state = .playing(speed: self.downloadSpeed, seeds: self.seedsCount, progress: self.progress)
                    }
                }
            }
        }
    }

    private static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec <= 0 {
            return "0 KB/s"
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
        }
    }

    public func stopStream() {
        activeTask?.cancel()
        activeTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        if let handle = currentHandle {
            Task { await handle.pause() }
        }
        currentHandle = nil
        if let session = torrentSession { Task { try? await session.shutdown() } }
        torrentSession = nil
        inAppServer.stop()
        state = .idle
        streamURL = nil
        currentTorrent = nil
        currentMovie = nil
        downloadSpeed = "0 KB/s"
        seedsCount = 0
        progress = 0
    }
}
