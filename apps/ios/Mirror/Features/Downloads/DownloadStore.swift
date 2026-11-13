import SwiftUI
import FirebaseAuth
import CryptoKit

@MainActor
protocol OfflineDownloadSource: AnyObject {
    func open(hash: String) async throws -> URL
    func subtitles(imdb: String, language: String) async throws -> SubtitleTrack
    func close()
}
extension PlaybackService: OfflineDownloadSource {}

@MainActor @Observable
final class DownloadStore: NSObject {
    static let shared = DownloadStore()
    private(set) var records: [OfflineDownload] = []
    private(set) var liveBytes: Int64 = 0
    var error: String?
    private var uid: String?
    private var root: URL?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var runningID: Int?
    private var preparation: Task<Void, Never>?
    private var networkTask: URLSessionDownloadTask?
    private var service: (any OfflineDownloadSource)?
    private var filesInUse: Set<URL> = []
    private var obsoleteFiles: Set<URL> = []
    private var renewals = 0
    private var started = false
    private var restoring = false
    private let storageDirectory: URL?
    private let accountProvider: () -> String?
    private let sourceFactory: @MainActor () -> any OfflineDownloadSource
    private let transferConfiguration: (() -> URLSessionConfiguration)?

    init(storageDirectory: URL? = nil,
         accountProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid },
         sourceFactory: @escaping @MainActor () -> any OfflineDownloadSource = { PlaybackService() },
         transferConfiguration: (() -> URLSessionConfiguration)? = nil) {
        self.storageDirectory = storageDirectory; self.accountProvider = accountProvider
        self.sourceFactory = sourceFactory; self.transferConfiguration = transferConfiguration
        super.init()
    }
    func shutdown() {
        stopRunning(); session.invalidateAndCancel()
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        authHandle = nil
    }
    private var backgroundCompletion: (() -> Void)?
    private let delegate = DownloadTransferDelegate()
    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = transferConfiguration?() ?? URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        delegate.owner = self
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    static var sessionIdentifier: String { (Bundle.main.bundleIdentifier ?? "com.mirror.app") + ".offline-downloads" }

    func start() {
        guard !started else { return }
        started = true
        loadAccount(accountProvider())
        guard storageDirectory == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in if self?.uid != user?.uid { self?.loadAccount(user?.uid) } }
        }
    }
    func backgroundEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == Self.sessionIdentifier else { completion(); return }
        backgroundCompletion = completion; start(); _ = session
    }
    func eventsFinished() {
        let completion = backgroundCompletion; backgroundCompletion = nil; completion?()
    }
    private func loadAccount(_ account: String?) {
        stopRunning(); records = []; root = nil; uid = account; error = nil; restoring = true
        guard let account else { restoring = false; return }
        do {
            let key = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
            let base = try storageDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("OfflineMovies", isDirectory: true)
            var directory = base.appendingPathComponent(key, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
            root = directory
            let manifest = directory.appendingPathComponent("downloads.json")
            if FileManager.default.fileExists(atPath: manifest.path) { records = try JSONDecoder().decode([OfflineDownload].self, from: Data(contentsOf: manifest)) }
            // Remove old replacement files left behind by a terminated player.
            for record in records {
                let folder = directory.appendingPathComponent(String(record.id))
                for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                    where file.pathExtension == "mp4" && file.lastPathComponent != record.asset?.file && !filesInUse.contains(file) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            // Reattach OS-owned background transfers before scheduling any new request.
            session.getAllTasks { [weak self] tasks in
                Task { @MainActor in
                    guard let self, self.uid == account else { return }
                    var attached = false
                    for task in tasks {
                        guard let ticket = TransferTicket.decode(task.taskDescription), ticket.account == account,
                              let record = self.records.first(where: { $0.id == ticket.movieID && $0.generation == ticket.generation }),
                              record.status == .downloading, record.bytes == ticket.offset, !attached,
                              let download = task as? URLSessionDownloadTask else { task.cancel(); continue }
                        self.runningID = record.id; self.networkTask = download; download.resume(); attached = true
                    }
                    for index in self.records.indices where [.preparing, .downloading].contains(self.records[index].status) && self.records[index].id != self.runningID {
                        self.records[index].status = .paused
                    }
                    do { try self.persist() } catch { self.error = "Couldn’t save download information." }
                    self.restoring = false; self.pump()
                }
            }
        } catch { root = nil; restoring = false; self.error = "Couldn’t read downloads on this device. Your files have been kept." }
    }
    private func persist() throws {
        guard let root else { throw Failure.signedOut }
        try JSONEncoder().encode(records).write(to: root.appendingPathComponent("downloads.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func directory(_ id: Int) throws -> URL {
        guard let root else { throw Failure.signedOut }
        let url = root.appendingPathComponent(String(id), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return url
    }
    private func index(_ id: Int) -> Int? { records.firstIndex { $0.id == id } }
    private func current(_ ticket: TransferTicket) -> Int? {
        guard uid == ticket.account, let index = index(ticket.movieID), records[index].generation == ticket.generation else { return nil }
        return index
    }
    func enqueue(movie: MovieDetail, torrent: Torrent, languages: Set<String>) throws {
        start()
        guard uid != nil, uid == accountProvider(), root != nil else { throw Failure.signedOut }
        let previous = records.first { $0.id == movie.id }
        if runningID == movie.id { stopRunning() }
        var record = previous ?? OfflineDownload(movie: movie, torrent: torrent)
        if record.asset != nil, (try? playback(record)) == nil { record.asset = nil }
        record.notices = []
        if record.torrent.hash != torrent.hash {
            if let path = try? directory(record.id).appendingPathComponent(record.partialFile) { try? FileManager.default.removeItem(at: path) }
            record.bytes = 0; record.total = 0; record.partialFile = UUID().uuidString + ".part"
        }
        record.movie = movie; record.torrent = torrent; record.generation = UUID(); record.status = .queued
        record.requestedSubtitles = Set(record.subtitles.keys).union(languages.intersection(SubtitleLanguage.codes))
        record.subtitleRequestsFinished.formUnion(record.subtitles.keys)
        record.failure = nil; record.updatedAt = Date(); record.streamURL = nil
        // Re-selecting a failed subtitle download retries it without re-downloading the video.
        record.subtitleRequestsFinished.subtract(languages.filter { record.subtitles[$0] == nil })
        if !record.needsVideo { record.bytes = record.asset!.size; record.total = record.asset!.size }
        if let i = index(record.id) { records[i] = record } else { records.insert(record, at: 0) }
        try persist(); pump()
    }
    func pause(_ id: Int) {
        guard let i = index(id) else { return }
        if runningID == id { stopRunning() }
        records[i].generation = UUID(); records[i].status = .paused; records[i].streamURL = nil
        saveOrReport(); pump()
    }
    func resume(_ id: Int) {
        guard let i = index(id) else { return }
        records[i].generation = UUID(); records[i].status = .queued; records[i].failure = nil
        records[i].streamURL = nil; saveOrReport(); pump()
    }
    func delete(_ id: Int) throws {
        if runningID == id { stopRunning() }
        if let root {
            let directory = root.appendingPathComponent(String(id))
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
        records.removeAll { $0.id == id }; try persist(); pump()
    }
    func deleteAll() throws { for id in records.map(\.id) { try delete(id) } }
    func poster(_ record: OfflineDownload) -> URL? {
        if let file = record.posterFile, let root { return root.appendingPathComponent(String(record.id)).appendingPathComponent(file) }
        return record.movie.posterURL
    }
    func playback(_ record: OfflineDownload) throws -> OfflineMovie {
        guard let asset = record.asset, let root else { throw Failure.missingFile }
        let directory = root.appendingPathComponent(String(record.id)), file = directory.appendingPathComponent(asset.file)
        guard (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ Int64($0) == asset.size }) == true else { throw Failure.missingFile }
        let tracks = record.subtitles.compactMapValues { name -> URL? in
            let url = directory.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return OfflineMovie(movie: record.movie, file: file, quality: MovieQuality.label(asset.quality), subtitles: tracks, position: record.position, lastPlayedAt: record.lastPlayedAt)
    }
    func retainPlaybackFile(_ url: URL) { filesInUse.insert(url) }
    func releasePlaybackFile(_ url: URL) {
        filesInUse.remove(url)
        if obsoleteFiles.remove(url) != nil { try? FileManager.default.removeItem(at: url) }
    }
    private func retireFile(_ url: URL) {
        if filesInUse.contains(url) { obsoleteFiles.insert(url) }
        else { try? FileManager.default.removeItem(at: url) }
    }
    func diskUsage() -> (downloads: Int64, used: Int64, free: Int64) {
        guard let root, let attributes = try? FileManager.default.attributesOfFileSystem(forPath: root.path) else { return (0, 0, 0) }
        let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        var bytes: Int64 = 0
        if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            for case let file as URL in files {
                if let value = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), value.isRegularFile == true { bytes += Int64(value.fileSize ?? 0) }
            }
        }
        return (bytes, total - free, free)
    }
    func updatePlayback(id: Int, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, position >= 0, duration > 0, let i = index(id) else { return }
        records[i].position = position; records[i].duration = duration; records[i].lastPlayedAt = Date(); saveOrReport()
    }
    private func saveOrReport() { do { try persist(); error = nil } catch { self.error = "Couldn’t save download information. Check free storage." } }
    private func stopRunning() {
        // Restored background transfers outlive the PlaybackService that created their lease.
        if service == nil, let id = runningID, let url = records.first(where: { $0.id == id })?.streamURL,
           url.path.range(of: #"^/v1/sessions/[a-f0-9-]{36}/video\.mp4$"#, options: .regularExpression) != nil {
            var request = URLRequest(url: url.deletingLastPathComponent()); request.httpMethod = "DELETE"
            URLSession.shared.dataTask(with: request).resume()
        }
        preparation?.cancel(); preparation = nil; networkTask?.cancel(); networkTask = nil
        service?.close(); service = nil; runningID = nil; liveBytes = 0
    }
    private func pump() {
        guard !restoring, runningID == nil, error == nil, let record = records.first(where: { $0.status == .queued }), let uid else { return }
        runningID = record.id; renewals = 0
        prepare(TransferTicket(account: uid, movieID: record.id, generation: record.generation, offset: 0, end: 0, total: 0))
    }
    private func prepare(_ ticket: TransferTicket) {
        preparation?.cancel()
        preparation = Task { @MainActor in
            guard let i = current(ticket) else { return }
            records[i].status = .preparing; saveOrReport()
            let source = sourceFactory(); service = source
            do {
                try await prepareExtras(ticket, source: source)
                try Task.checkCancellation()
                guard let i = current(ticket) else { return }
                if !records[i].needsVideo { finish(ticket); return }
                let hash = records[i].torrent.hash
                let url = try await source.open(hash: hash)
                try Task.checkCancellation()
                var request = URLRequest(url: url); request.httpMethod = "HEAD"; request.timeoutInterval = 60
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.expectedContentLength > 0 else { throw Failure.invalidResponse }
                guard let i = current(ticket) else { return }
                let total = response.expectedContentLength
                if records[i].total > 0, records[i].total != total { throw Failure.invalidResponse }
                let directory = try directory(ticket.movieID)
                let file = directory.appendingPathComponent(records[i].partialFile)
                let actual = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                if actual < records[i].bytes { records[i].bytes = 0 }
                let available = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? Int64.max
                guard total - records[i].bytes + 32 * 1024 * 1024 < available else { throw Failure.storage }
                records[i].total = total; records[i].streamURL = url; records[i].status = .downloading
                try persist(); scheduleNext(ticket)
            } catch is CancellationError { } catch {
                if !Task.isCancelled { fail(ticket, message: (error as? Failure)?.localizedDescription ?? "Couldn’t download this movie. Check your connection and try again.") }
            }
        }
    }
    private func prepareExtras(_ ticket: TransferTicket, source: any OfflineDownloadSource) async throws {
        guard let i = current(ticket) else { throw CancellationError() }
        let movie = records[i].movie
        if records[i].posterFile == nil, let url = movie.posterURL {
            if let (file, response) = try? await URLSession.shared.download(from: url) {
                defer { try? FileManager.default.removeItem(at: file) }
                if (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength < 10 * 1024 * 1024,
                   let i = current(ticket), !Task.isCancelled {
                    let target = try directory(ticket.movieID).appendingPathComponent("poster.jpg")
                    try? FileManager.default.removeItem(at: target); try FileManager.default.moveItem(at: file, to: target)
                    records[i].posterFile = "poster.jpg"; try persist()
                }
            }
        }
        guard let i = current(ticket) else { throw CancellationError() }
        let pending = records[i].requestedSubtitles.subtracting(records[i].subtitleRequestsFinished)
        for code in SubtitleLanguage.codes where pending.contains(code) {
            try Task.checkCancellation()
            do {
                let track = try await source.subtitles(imdb: movie.imdbCode, language: code)
                try Task.checkCancellation()
                guard !SubtitleParser.parse(track.text).isEmpty, SubtitleLanguage.codes.contains(track.language) else { throw Failure.invalidResponse }
                guard let i = current(ticket) else { throw CancellationError() }
                let name = "subtitle-\(track.language).srt"
                try Data(track.text.utf8).write(to: directory(ticket.movieID).appendingPathComponent(name), options: .atomic)
                records[i].subtitles[track.language] = name
                records[i].subtitleRequestsFinished.insert(code)
                if code != track.language {
                    let notice = "\(SubtitleLanguage.name(code)) unavailable; English downloaded instead."
                    if !records[i].notices.contains(notice) { records[i].notices.append(notice) }
                }
                try persist()
            } catch is CancellationError { throw CancellationError() }
            catch {
                guard let i = current(ticket), !Task.isCancelled else { throw CancellationError() }
                let notice = "\(SubtitleLanguage.name(code)) subtitles couldn’t download. You can retry from Download Settings."
                if !records[i].notices.contains(notice) { records[i].notices.append(notice) }
                records[i].subtitleRequestsFinished.insert(code); try persist()
            }
        }
    }
    private func scheduleNext(_ ticket: TransferTicket) {
        guard let i = current(ticket), let url = records[i].streamURL, records[i].status == .downloading else { return }
        let record = records[i]
        if record.bytes == record.total { completeVideo(ticket); return }
        let end = DownloadRange.end(offset: record.bytes, total: record.total)
        let next = TransferTicket(account: ticket.account, movieID: ticket.movieID, generation: ticket.generation, offset: record.bytes, end: end, total: record.total)
        var request = URLRequest(url: url); request.setValue("bytes=\(record.bytes)-\(end)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 120
        request.allowsCellularAccess = true // Wi-Fi preference is a visual placeholder for now.
        let task = session.downloadTask(with: request); task.taskDescription = next.encoded
        networkTask = task; task.resume()
    }
    func progress(_ ticket: TransferTicket, bytes: Int64) {
        guard let i = current(ticket), records[i].bytes == ticket.offset, runningID == ticket.movieID else { return }
        liveBytes = max(0, min(bytes, ticket.end - ticket.offset + 1))
    }
    func received(_ ticket: TransferTicket, file: URL, response: HTTPURLResponse?) {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let i = current(ticket), records[i].status == .downloading, records[i].bytes == ticket.offset else { return }
        networkTask = nil; liveBytes = 0
        if response?.statusCode == 404, renewals < 2 {
            renewals += 1; service?.close(); prepare(ticket); return
        }
        do {
            let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard response?.statusCode == 206, DownloadRange.valid(header: response?.value(forHTTPHeaderField: "Content-Range"), offset: ticket.offset, end: ticket.end, total: ticket.total, size: size) else { throw Failure.invalidResponse }
            try DownloadRange.append(chunk: file, to: directory(ticket.movieID).appendingPathComponent(records[i].partialFile), offset: ticket.offset)
            records[i].bytes = ticket.end + 1; try persist(); scheduleNext(ticket)
        } catch { fail(ticket, message: (error as? Failure)?.localizedDescription ?? "Couldn’t save this download. Check free storage and try again.") }
    }
    func transferFailed(_ ticket: TransferTicket, error: Error) {
        guard let i = current(ticket), records[i].status == .downloading, records[i].bytes == ticket.offset else { return }
        fail(ticket, message: "Download interrupted. Check your connection and tap Retry to continue.")
    }
    private func completeVideo(_ ticket: TransferTicket) {
        guard let i = current(ticket) else { return }
        do {
            let directory = try directory(ticket.movieID), old = records[i].asset
            let name = UUID().uuidString + ".mp4"
            try FileManager.default.moveItem(at: directory.appendingPathComponent(records[i].partialFile), to: directory.appendingPathComponent(name))
            records[i].asset = .init(file: name, quality: records[i].torrent.quality, hash: records[i].torrent.hash, size: records[i].total)
            try persist()
            if let old { retireFile(directory.appendingPathComponent(old.file)) }
            finish(ticket)
        } catch { fail(ticket, message: "Couldn’t finish saving this movie. Check free storage and retry.") }
    }
    private func finish(_ ticket: TransferTicket) {
        guard let i = current(ticket) else { return }
        records[i].status = .completed; records[i].failure = nil
        stopRunning(); records[i].streamURL = nil; saveOrReport(); pump()
    }
    private func fail(_ ticket: TransferTicket, message: String) {
        guard let i = current(ticket) else { return }
        records[i].status = .failed; records[i].failure = message
        stopRunning(); records[i].streamURL = nil; saveOrReport(); pump()
    }
    enum Failure: LocalizedError {
        case signedOut, storage, invalidResponse, missingFile
        var errorDescription: String? {
            switch self {
            case .signedOut: return "Sign in to download movies on this device."
            case .storage: return "There isn’t enough free space for this movie."
            case .invalidResponse: return "The download couldn’t be verified. Please retry."
            case .missingFile: return "This movie’s downloaded file is missing. Download it again."
            }
        }
    }
}

struct TransferTicket: Codable {
    let account: String
    let movieID: Int
    let generation: UUID
    let offset: Int64
    let end: Int64
    let total: Int64
    var encoded: String? { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } }
    static func decode(_ value: String?) -> Self? { value.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } }
}

private final class DownloadTransferDelegate: NSObject, URLSessionDownloadDelegate {
    private var lastProgress: TimeInterval = 0
    weak var owner: DownloadStore?
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let ticket = TransferTicket.decode(downloadTask.taskDescription) else { return }
        let durable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".download-chunk")
        do {
            try FileManager.default.moveItem(at: location, to: durable)
            let response = downloadTask.response as? HTTPURLResponse
            DispatchQueue.main.async { [weak self] in
                guard let owner = self?.owner else { try? FileManager.default.removeItem(at: durable); return }
                owner.received(ticket, file: durable, response: response)
            }
        } catch { DispatchQueue.main.async { [weak self] in self?.owner?.transferFailed(ticket, error: error) } }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastProgress >= 0.25 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastProgress = now
        guard let ticket = TransferTicket.decode(downloadTask.taskDescription) else { return }
        DispatchQueue.main.async { [weak self] in self?.owner?.progress(ticket, bytes: totalBytesWritten) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let ticket = TransferTicket.decode(task.taskDescription) else { return }
        DispatchQueue.main.async { [weak self] in self?.owner?.transferFailed(ticket, error: error) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in self?.owner?.eventsFinished() }
    }
}
