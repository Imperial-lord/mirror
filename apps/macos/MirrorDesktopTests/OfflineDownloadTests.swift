import AVFoundation
import Network
import XCTest

@testable import MirrorDesktop

@MainActor
final class OfflineDownloadTests: XCTestCase {
  func testRejectsWrongRangesAndTruncatedResponses() {
    XCTAssertTrue(
      DownloadRange.valid(header: "bytes 10-19/30", offset: 10, end: 19, total: 30, size: 10))
    XCTAssertFalse(
      DownloadRange.valid(header: "bytes 0-9/30", offset: 10, end: 19, total: 30, size: 10))
    XCTAssertFalse(
      DownloadRange.valid(header: "bytes 10-19/30", offset: 10, end: 19, total: 30, size: 9))
    XCTAssertFalse(DownloadRange.valid(header: nil, offset: 0, end: 9, total: 30, size: 10))
    XCTAssertEqual(DownloadRange.end(offset: 20, total: 30), 29)
  }

  func testAppendRecoversCrashWithoutDuplicatingCommittedBytes() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let partial = folder.appendingPathComponent("video.part")
    let chunk = folder.appendingPathComponent("chunk")
    try Data("ABCstale-uncommitted-data".utf8).write(to: partial)
    try Data("DEF".utf8).write(to: chunk)
    try DownloadRange.append(chunk: chunk, to: partial, offset: 3)
    XCTAssertEqual(try Data(contentsOf: partial), Data("ABCDEF".utf8))
    try DownloadRange.append(chunk: chunk, to: partial, offset: 3)
    XCTAssertEqual(try Data(contentsOf: partial), Data("ABCDEF".utf8))
    XCTAssertThrowsError(try DownloadRange.append(chunk: chunk, to: partial, offset: 9))
    XCTAssertThrowsError(try DownloadRange.append(chunk: chunk, to: partial, offset: -1))
  }

  func testRealTransfersResumeReplaceQualityAccumulateSubtitlesAndPlayWithoutNetwork() async throws
  {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clip = try await makeClip(in: folder)
    var body = try Data(contentsOf: clip)
    // A legal MP4 free box makes this span two transfer windows without a large video fixture.
    let padding = Int(DownloadRange.chunkSize) + 127
    var length = UInt32(padding).bigEndian
    withUnsafeBytes(of: &length) { body.append(contentsOf: $0) }
    body.append(Data("free".utf8))
    body.append(Data(repeating: 0, count: padding - 8))
    let server = try DownloadFixtureServer(body: body, failOnceAt: Int(DownloadRange.chunkSize))
    try await server.start()
    defer { server.stop() }
    let source = FixtureDownloadSource(url: server.url)
    let storage = folder.appendingPathComponent("library")
    let store = DownloadStore(
      storageDirectory: storage, accountProvider: { "download-test-account" },
      sourceFactory: { source }, transferConfiguration: { .ephemeral })
    defer { store.shutdown() }
    let movie = try fixtureMovie()
    let hd = try fixtureTorrent(quality: "1080p", hash: String(repeating: "a", count: 40))
    try store.enqueue(movie: movie, torrent: hd, languages: ["en", "fr"])
    try await until { store.records.first?.status == .failed }
    XCTAssertEqual(store.records.first?.bytes, DownloadRange.chunkSize)
    XCTAssertNil(store.records.first?.asset)
    let failed = try XCTUnwrap(store.records.first)
    store.pause(movie.id)
    let staleChunk = folder.appendingPathComponent("stale-chunk")
    try Data("stale".utf8).write(to: staleChunk)
    store.received(
      TransferTicket(
        account: "download-test-account", movieID: movie.id, generation: failed.generation,
        offset: failed.bytes, end: failed.total - 1, total: failed.total), file: staleChunk,
      response: nil)
    XCTAssertEqual(store.records.first?.status, .paused)
    XCTAssertEqual(store.records.first?.bytes, DownloadRange.chunkSize)
    store.resume(movie.id)
    try await until { store.records.first?.status == .completed }
    let first = try XCTUnwrap(store.records.first)
    XCTAssertEqual(server.offsets, [0, Int(DownloadRange.chunkSize), Int(DownloadRange.chunkSize)])
    let firstPlayback = try store.playback(first)
    XCTAssertEqual(try Data(contentsOf: firstPlayback.file), body)
    XCTAssertEqual(Set(first.subtitles.keys), ["en", "fr"])
    store.updatePlayback(id: movie.id, position: 1, duration: 3)

    // Adding another subtitle language reuses the existing video instead of downloading it again.
    try store.enqueue(movie: movie, torrent: hd, languages: ["es"])
    try await until { store.records.first?.status == .completed }
    XCTAssertEqual(store.records.first?.asset?.file, first.asset?.file)
    XCTAssertEqual(server.offsets.count, 3)
    XCTAssertEqual(
      Set(store.records.first?.subtitles.keys ?? [String: String]().keys), ["en", "fr", "es"])

    store.retainPlaybackFile(firstPlayback.file)
    let sd = try fixtureTorrent(quality: "720p", hash: String(repeating: "b", count: 40))
    try store.enqueue(movie: movie, torrent: sd, languages: [])
    XCTAssertEqual(
      store.records.first?.asset?.quality, "1080p",
      "Keep the playable version until its replacement succeeds")
    try await until { store.records.first?.status == .completed }
    let replacement = try XCTUnwrap(store.records.first)
    let playback = try store.playback(replacement)
    XCTAssertEqual(replacement.asset?.quality, "720p")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: firstPlayback.file.path),
      "An open player keeps its old file until dismissed")
    store.releasePlaybackFile(firstPlayback.file)
    XCTAssertFalse(FileManager.default.fileExists(atPath: firstPlayback.file.path))
    XCTAssertEqual(playback.position, 1)
    XCTAssertEqual(Set(playback.subtitles.keys), ["en", "fr", "es"])
    let files = try FileManager.default.contentsOfDirectory(
      at: playback.file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
    XCTAssertEqual(files.filter { $0.pathExtension == "mp4" }.count, 1)

    // The origin is gone; the saved MP4 and captions must be sufficient for AVPlayer.
    server.stop()
    let asset = AVURLAsset(url: playback.file)
    let playable = try await asset.load(.isPlayable)
    XCTAssertTrue(playable)
    let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    try await until { player.currentItem?.status == .readyToPlay }
    let sought = await player.seek(
      to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero
    )
    XCTAssertTrue(sought)
    XCTAssertEqual(player.currentTime().seconds, 1, accuracy: 0.1)
    for file in playback.subtitles.values {
      XCTAssertFalse(SubtitleParser.parse(try String(contentsOf: file)).isEmpty)
    }
    player.pause()

    // A new store reconstructs the device library and watch position from disk.
    let restored = DownloadStore(
      storageDirectory: storage, accountProvider: { "download-test-account" },
      sourceFactory: { source }, transferConfiguration: { .ephemeral })
    restored.start()
    defer { restored.shutdown() }
    try await until { restored.records.count == 1 }
    XCTAssertEqual(restored.records.first?.position, 1)
    XCTAssertEqual(restored.records.first?.asset?.quality, "720p")
    let otherAccount = DownloadStore(
      storageDirectory: storage, accountProvider: { "different-account" },
      sourceFactory: { source }, transferConfiguration: { .ephemeral })
    otherAccount.start()
    defer { otherAccount.shutdown() }
    XCTAssertTrue(otherAccount.records.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: playback.file.path))
    try FileManager.default.removeItem(at: playback.file)
    try restored.enqueue(movie: movie, torrent: sd, languages: [])
    XCTAssertNil(
      restored.records.first?.asset, "A missing file must be downloaded again, not marked ready")
    restored.pause(movie.id)
    try restored.delete(movie.id)
    XCTAssertTrue(restored.records.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: playback.file.path))
  }

  func testNativePlayerResumesSeeksAndRestrictsOfflineChoices() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clip = try await makeClip(in: folder)
    let subtitles = folder.appendingPathComponent("en.srt")
    try "1\n00:00:00,000 --> 00:00:02,000\nA local story.\n".write(
      to: subtitles, atomically: true, encoding: .utf8)
    let movie = try fixtureMovie()
    let offline = OfflineMovie(
      movie: movie, file: clip, quality: "HD 720", subtitles: ["en": subtitles], position: 1,
      lastPlayedAt: Date())
    let source = FixtureDownloadSource(url: clip)
    let player = DesktopPlayerController(source: source, resumeProvider: { _ in nil })
    defer { player.stop() }
    player.start(DesktopPlayback(movie: movie, offline: offline))
    try await until { player.ready && !player.loading }
    XCTAssertEqual(player.qualityLabel, "HD 720")
    XCTAssertEqual(player.subtitleChoices, ["en"])
    XCTAssertTrue(player.offline)
    player.wantsPlay = false
    player.player.pause()
    player.seek(0.5)
    try await until { abs(player.player.currentTime().seconds - 0.5) < 0.4 }
    player.setSpeed(1.5)
    XCTAssertEqual(player.rate, 1.5)
    player.setVolume(0.3)
    XCTAssertEqual(player.player.volume, 0.3)
    player.stop()
    XCTAssertNil(player.player.currentItem)
  }

  func testHTTPPlayerResumeSeekAndSessionCleanup() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let clip = try await makeClip(in: folder)
    let server = try DownloadFixtureServer(body: Data(contentsOf: clip), failOnceAt: nil)
    try await server.start()
    defer { server.stop() }
    let torrent = try fixtureTorrent(quality: "1080p", hash: String(repeating: "a", count: 40))
    var data = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(fixtureMovie())) as? [String: Any])
    data["torrents"] = [try JSONSerialization.jsonObject(with: JSONEncoder().encode(torrent))]
    let movie = try JSONDecoder().decode(
      MovieDetail.self, from: JSONSerialization.data(withJSONObject: data))
    let source = FixtureDownloadSource(url: server.url)
    let player = DesktopPlayerController(source: source, resumeProvider: { _ in (1, Date()) })
    defer { player.stop() }
    player.start(DesktopPlayback(movie: movie))
    try await until { player.ready && !player.loading }
    player.wantsPlay = false
    player.player.pause()
    try await until { player.player.currentTime().seconds >= 0.7 }
    XCTAssertFalse(player.offline)
    XCTAssertEqual(player.qualityLabel, "Full HD 1080")
    player.seek(0.3)
    try await until { abs(player.player.currentTime().seconds - 0.3) < 0.3 }
    let before = source.closeCount
    player.stop()
    XCTAssertGreaterThan(source.closeCount, before)
    XCTAssertNil(player.player.currentItem)
  }

  private func until(_ condition: () -> Bool) async throws {
    let limit = Date().addingTimeInterval(25)
    while !condition() {
      guard Date() < limit else {
        XCTFail("Download condition timed out")
        throw URLError(.timedOut)
      }
      try await Task.sleep(for: .milliseconds(25))
    }
  }
  private func fixtureMovie() throws -> MovieDetail {
    try JSONDecoder().decode(
      MovieDetail.self,
      from: Data(
        #"{"id":999990001,"url":"","imdb_code":"tt0000001","title":"Offline test clip","year":2026,"rating":0,"runtime":1,"genres":["Drama"]}"#
          .utf8))
  }
  private func fixtureTorrent(quality: String, hash: String) throws -> Torrent {
    let data = try JSONSerialization.data(withJSONObject: [
      "url": "", "hash": hash, "quality": quality, "type": "bluray", "seeds": 1, "peers": 1,
      "size": "16 MB", "size_bytes": 16 * 1024 * 1024, "date_uploaded": "",
    ])
    return try JSONDecoder().decode(Torrent.self, from: data)
  }
  private func makeClip(in folder: URL) async throws -> URL {
    let url = folder.appendingPathComponent("fixture.mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
      ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
      ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<6 {
      while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
      var pixel: CVPixelBuffer?
      CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32BGRA, nil, &pixel)
      let buffer = try XCTUnwrap(pixel)
      CVPixelBufferLockBaseAddress(buffer, [])
      memset(
        CVPixelBufferGetBaseAddress(buffer), Int32(frame * 30), CVPixelBufferGetDataSize(buffer))
      CVPixelBufferUnlockBaseAddress(buffer, [])
      XCTAssertTrue(
        adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 2)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    if let error = writer.error { throw error }
    return url
  }
}

@MainActor
private final class FixtureDownloadSource: OfflineDownloadSource {
  let url: URL
  init(url: URL) { self.url = url }
  func open(hash: String) async throws -> URL { url }
  var closeCount = 0
  func close() { closeCount += 1 }
  func subtitles(imdb: String, language: String) async throws -> SubtitleTrack {
    SubtitleTrack(
      language: language, requestedLanguage: language,
      text: "1\n00:00:00,000 --> 00:00:02,000\nOffline caption \(language)\n")
  }
}

private final class DownloadFixtureServer: @unchecked Sendable {
  let listener: NWListener
  let body: Data
  private let queue = DispatchQueue(label: "mirror-download-fixture")
  private var failOnceAt: Int?
  private var requests: [Int] = []
  private var readyContinuation: CheckedContinuation<Void, Error>?
  var offsets: [Int] { queue.sync { requests } }
  var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/video.mp4")! }
  init(body: Data, failOnceAt: Int?) throws {
    self.body = body
    self.failOnceAt = failOnceAt
    listener = try NWListener(using: .tcp, on: .any)
  }
  func start() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      readyContinuation = continuation
      listener.stateUpdateHandler = { [weak self] state in
        guard let self, let ready = self.readyContinuation else { return }
        switch state {
        case .ready:
          self.readyContinuation = nil
          ready.resume()
        case .failed(let error):
          self.readyContinuation = nil
          ready.resume(throwing: error)
        default: break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        guard let self else {
          connection.cancel()
          return
        }
        connection.start(queue: self.queue)
        self.receive(connection, data: Data())
      }
      listener.start(queue: queue)
    }
  }
  func stop() { listener.cancel() }
  private func receive(_ connection: NWConnection, data: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
      [weak self] part, _, _, error in
      guard let self, let part, error == nil else {
        connection.cancel()
        return
      }
      var data = data
      data.append(part)
      guard let request = String(data: data, encoding: .utf8), request.contains("\r\n\r\n") else {
        self.receive(connection, data: data)
        return
      }
      if request.hasPrefix("HEAD") {
        self.send(
          connection, status: "200 OK", headers: "Content-Length: \(self.body.count)\r\n",
          data: Data())
        return
      }
      guard
        let range = request.components(separatedBy: "\r\n").first(where: {
          $0.lowercased().hasPrefix("range:")
        })?.components(separatedBy: "bytes=").last,
        let start = Int(range.components(separatedBy: "-")[0]),
        let end = Int(range.components(separatedBy: "-")[1]), end < self.body.count
      else {
        self.send(
          connection, status: "400 Bad Request", headers: "Content-Length: 0\r\n", data: Data())
        return
      }
      self.requests.append(start)
      if start == self.failOnceAt {
        self.failOnceAt = nil
        self.send(
          connection, status: "503 Unavailable", headers: "Content-Length: 0\r\n", data: Data())
        return
      }
      let bytes = self.body.subdata(in: start..<(end + 1))
      self.send(
        connection, status: "206 Partial Content",
        headers:
          "Content-Length: \(bytes.count)\r\nContent-Range: bytes \(start)-\(end)/\(self.body.count)\r\n",
        data: bytes)
    }
  }
  private func send(_ connection: NWConnection, status: String, headers: String, data: Data) {
    var response = Data(
      "HTTP/1.1 \(status)\r\n\(headers)Content-Type: video/mp4\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
        .utf8)
    response.append(data)
    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
  }
}
