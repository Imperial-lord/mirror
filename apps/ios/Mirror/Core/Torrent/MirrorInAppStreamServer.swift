import Foundation
import Network

/// Lightweight embedded in-process HTTP streaming server for AVPlayer.
/// Runs 100% on localhost within the app, supporting HTTP 206 Partial Content range requests.
public final class MirrorInAppStreamServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.mirror.inappserver", qos: .userInitiated)
    public private(set) var port: UInt16 = 0
    private var videoFileURL: URL?
    private var videoFileSize: Int64 = 0
    private var pieceLength: Int = 0
    private var fileOffsetInTorrent: Int64 = 0
    private var isPieceReady: (@Sendable (Int) -> Bool)?

    public var onReadRequested: (@Sendable (Int64, Int64) -> Void)?

    public init() {}

    public func start(
        videoFileURL: URL,
        expectedSize: Int64,
        pieceLength: Int = 0,
        fileOffsetInTorrent: Int64 = 0,
        isPieceReady: (@Sendable (Int) -> Bool)? = nil
    ) async throws -> URL {
        stop()
        self.videoFileURL = videoFileURL
        self.videoFileSize = expectedSize
        self.pieceLength = pieceLength
        self.fileOffsetInTorrent = fileOffsetInTorrent
        self.isPieceReady = isPieceReady

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let nwListener = try NWListener(using: params)

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            nwListener.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    if let assignedPort = nwListener.port?.rawValue {
                        resumed = true
                        self?.port = assignedPort
                        self?.listener = nwListener
                        let url = URL(string: "http://127.0.0.1:\(assignedPort)/video.mp4")!
                        print("[InAppStreamServer] Started successfully on port \(assignedPort)")
                        continuation.resume(returning: url)
                    }
                case .failed(let error):
                    resumed = true
                    print("[InAppStreamServer] Failed to bind: \(error)")
                    continuation.resume(throwing: error)
                case .cancelled:
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: NSError(
                            domain: "MirrorInAppStreamServer",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Server was cancelled"]
                        ))
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            self.listener = nwListener
            nwListener.start(queue: self.queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        videoFileURL = nil
        isPieceReady = nil
        onReadRequested = nil
        pieceLength = 0
        fileOffsetInTorrent = 0
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self, let data = data, !data.isEmpty, error == nil else {
                connection.cancel()
                return
            }

            guard let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            self.respond(to: requestString, connection: connection)
        }
    }

    private func respond(to request: String, connection: NWConnection) {
        guard let videoFileURL = self.videoFileURL else {
            sendResponse(connection: connection, header: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n", body: nil)
            return
        }

        let isHead = request.hasPrefix("HEAD")
        let totalSize = videoFileSize > 0 ? videoFileSize : (try? FileManager.default.attributesOfItem(atPath: videoFileURL.path)[.size] as? Int64) ?? 0

        // Parse Range: bytes=start-end
        var start: Int64 = 0
        var end: Int64 = max(0, totalSize - 1)
        var isRange = false

        let lines = request.components(separatedBy: "\r\n")
        if let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }) {
            let parts = rangeLine.components(separatedBy: "=")
            if parts.count == 2 {
                let bounds = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: "-")
                if let s = Int64(bounds[0]) {
                    start = s
                    isRange = true
                }
                if bounds.count > 1, let e = Int64(bounds[1]), e > 0 {
                    end = min(e, totalSize - 1)
                }
            }
        }

        guard totalSize > 0, start >= 0, start < totalSize, end >= start else {
            sendResponse(connection: connection, header: "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(totalSize)\r\nContent-Length: 0\r\n\r\n", body: nil)
            return
        }
        let length = end - start + 1
        var headers = ""
        if isRange {
            headers = "HTTP/1.1 206 Partial Content\r\n"
            headers += "Content-Type: video/mp4\r\n"
            headers += "Accept-Ranges: bytes\r\n"
            headers += "Content-Range: bytes \(start)-\(end)/\(totalSize)\r\n"
            headers += "Content-Length: \(length)\r\n"
            headers += "Connection: close\r\n\r\n"
        } else {
            headers = "HTTP/1.1 200 OK\r\n"
            headers += "Content-Type: video/mp4\r\n"
            headers += "Accept-Ranges: bytes\r\n"
            headers += "Content-Length: \(totalSize)\r\n"
            headers += "Connection: close\r\n\r\n"
        }

        guard !isHead else {
            sendResponse(connection: connection, header: headers, body: nil)
            return
        }

        // Detect abandoned range requests while waiting on torrent data.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, complete, error in
            if complete || error != nil { connection.cancel() }
        }
        onReadRequested?(start, end)
        guard let headerData = headers.data(using: .utf8) else { connection.cancel(); return }
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            guard error == nil, let self = self else { connection.cancel(); return }
            self.streamFile(url: videoFileURL, offset: start, count: length, connection: connection)
        })
    }

    private func streamFile(url: URL, offset: Int64, count: Int64, connection: NWConnection) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            connection.cancel()
            return
        }

        var bytesRemaining = count
        var currentOffset = offset
        let chunkSize = 64 * 1024
        var waitRetries = 0
        var lastRequestedPiece: Int?

        func sendNextChunk() {
            switch connection.state {
            case .cancelled, .failed:
                try? handle.close()
                return
            default: break
            }
            guard bytesRemaining > 0 else {
                try? handle.close()
                connection.cancel()
                return
            }

            // Guard against sparse file 0-byte reads: wait for piece completion
            if self.pieceLength > 0, let checker = self.isPieceReady {
                let torrentByteOffset = self.fileOffsetInTorrent + currentOffset
                let pieceIndex = Int(torrentByteOffset / Int64(self.pieceLength))
                if !checker(pieceIndex) {
                    if lastRequestedPiece != pieceIndex {
                        self.onReadRequested?(currentOffset, min(offset + count - 1, currentOffset + Int64(self.pieceLength) * 16 - 1))
                        lastRequestedPiece = pieceIndex
                    }
                    waitRetries += 1
                    if waitRetries > 300 { // 30 seconds timeout waiting for piece
                        try? handle.close()
                        connection.cancel()
                        return
                    }
                    self.queue.asyncAfter(deadline: .now() + 0.1) {
                        sendNextChunk()
                    }
                    return
                }
            }
            waitRetries = 0

            var toRead = min(Int64(chunkSize), bytesRemaining)
            if self.pieceLength > 0 {
                let withinPiece = (self.fileOffsetInTorrent + currentOffset) % Int64(self.pieceLength)
                toRead = min(toRead, Int64(self.pieceLength) - withinPiece)
            }
            do {
                try handle.seek(toOffset: UInt64(currentOffset))
                let chunk = handle.readData(ofLength: Int(toRead))
                guard !chunk.isEmpty else {
                    self.queue.asyncAfter(deadline: .now() + 0.1) {
                        sendNextChunk()
                    }
                    return
                }

                currentOffset += Int64(chunk.count)
                bytesRemaining -= Int64(chunk.count)

                connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                    if error != nil {
                        try? handle.close()
                        connection.cancel()
                    } else {
                        self?.queue.async {
                            sendNextChunk()
                        }
                    }
                })
            } catch {
                try? handle.close()
                connection.cancel()
            }
        }

        sendNextChunk()
    }

    private func sendResponse(connection: NWConnection, header: String, body: Data?) {
        guard let headerData = header.data(using: .utf8) else { connection.cancel(); return }
        var fullData = headerData
        if let body = body { fullData.append(body) }
        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
