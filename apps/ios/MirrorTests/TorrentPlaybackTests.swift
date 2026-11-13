import XCTest
import SwiftTorrent
@testable import Mirror

final class TorrentPlaybackTests: XCTestCase {
    func testSeekPrioritiesOverrideSequentialDownloads() {
        var picker = PiecePicker(pieceCount: 100)
        var peers = Bitfield(count: 100)
        for i in 0..<100 { peers.set(i) }
        let completed = Bitfield(count: 100)
        picker.prioritize([70, 71, 72])
        XCTAssertEqual(picker.pick(have: completed, peerHas: peers), 70)
        picker.prioritize([40, 41])
        XCTAssertEqual(picker.pick(have: completed, peerHas: peers), 40)
    }

    func testCompletionDoesNotInventHeaderAvailability() {
        let tracker = CompletedPiecesTracker()
        tracker.markPieceCompleted(10)
        XCTAssertFalse(tracker.isPieceReady(0))
        XCTAssertTrue(tracker.isPieceReady(10))
        tracker.markPieceCompleted(0)
        XCTAssertTrue(tracker.isPieceReady(0))
    }

    func testRangeServerReturnsExactBytesAcrossPieces() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data((0..<128).map(UInt8.init))
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let server = MirrorInAppStreamServer()
        let url = try await server.start(videoFileURL: file, expectedSize: 128, pieceLength: 32, fileOffsetInTorrent: 7, isPieceReady: { _ in true })
        defer { server.stop() }
        var request = URLRequest(url: url)
        request.setValue("bytes=24-79", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(data, bytes.subdata(in: 24..<80))
        request.setValue("bytes=200-", forHTTPHeaderField: "Range")
        let (_, invalid) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode, 416)
    }
}
