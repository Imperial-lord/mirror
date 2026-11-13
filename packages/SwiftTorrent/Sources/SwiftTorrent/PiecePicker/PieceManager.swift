import Foundation
import Crypto

/// Tracks piece completion and verifies SHA-1 hashes.
public actor PieceManager {
    private let pieceCount: Int
    private let pieceLength: Int
    private let totalSize: Int64
    private let pieceHashes: Data  // concatenated 20-byte SHA-1 hashes
    private var completed: Bitfield
    private var inProgress: Set<Int>
    private var pieceBuffers: [Int: Data]
    private var receivedBlocks: [Int: Set<Int>]
    private var requestedBlocks: [Int: Set<Int>]

    public init(info: TorrentInfo) {
        self.pieceCount = info.pieceCount
        self.pieceLength = info.pieceLength
        self.totalSize = info.totalSize
        self.pieceHashes = info.pieces
        self.completed = Bitfield(count: info.pieceCount)
        self.inProgress = []
        self.pieceBuffers = [:]
        self.receivedBlocks = [:]
        self.requestedBlocks = [:]
    }

    /// Mark a piece as being downloaded.
    public func startPiece(_ index: Int) {
        guard !completed.get(index) else { return }
        if !inProgress.contains(index) {
            inProgress.insert(index)
            let size = expectedPieceSize(index)
            pieceBuffers[index] = Data(count: size)
            receivedBlocks[index] = []
            requestedBlocks[index] = []
        }
    }

    /// Add a block to a piece being downloaded.
    public func addBlock(pieceIndex: Int, offset: Int, data: Data) {
        guard inProgress.contains(pieceIndex), var buffer = pieceBuffers[pieceIndex] else { return }
        let blockIdx = offset / 16384
        receivedBlocks[pieceIndex]?.insert(blockIdx)

        let end = min(buffer.count, offset + data.count)
        if offset < end {
            buffer.replaceSubrange(offset..<end, with: data.prefix(end - offset))
            pieceBuffers[pieceIndex] = buffer
        }
    }

    /// Check if all blocks of a piece have been received.
    public func isPieceFullyReceived(_ index: Int) -> Bool {
        guard inProgress.contains(index) else { return false }
        let totalBlocks = blockCount(for: index)
        let receivedCount = receivedBlocks[index]?.count ?? 0
        return receivedCount >= totalBlocks
    }

    /// Returns the next unrequested block (offset and length) for a piece.
    public func nextBlockToRequest(pieceIndex: Int) -> (offset: Int, length: Int)? {
        guard inProgress.contains(pieceIndex),
              let received = receivedBlocks[pieceIndex],
              let requested = requestedBlocks[pieceIndex] else { return nil }

        let size = expectedPieceSize(pieceIndex)
        let totalBlocks = (size + 16383) / 16384
        for blockIdx in 0..<totalBlocks {
            if !received.contains(blockIdx) && !requested.contains(blockIdx) {
                let offset = blockIdx * 16384
                let length = min(16384, size - offset)
                return (offset, length)
            }
        }
        return nil
    }

    public func markBlockRequested(pieceIndex: Int, offset: Int) {
        let blockIdx = offset / 16384
        requestedBlocks[pieceIndex]?.insert(blockIdx)
    }

    public func unmarkBlockRequested(pieceIndex: Int, offset: Int) {
        let blockIdx = offset / 16384
        requestedBlocks[pieceIndex]?.remove(blockIdx)
    }

    public func getInProgressPieces() -> [Int] {
        Array(inProgress)
    }

    /// Verify and complete a piece.
    public func completePiece(_ index: Int) -> Bool {
        guard isPieceFullyReceived(index), let buffer = pieceBuffers[index] else { return false }

        // Verify hash
        let expectedHash = pieceHashes.subdata(in: index * 20..<(index + 1) * 20)
        let actualHash = Data(Insecure.SHA1.hash(data: buffer))

        guard actualHash == expectedHash else {
            // Hash mismatch — piece is corrupt, reset piece for redownload
            pieceBuffers.removeValue(forKey: index)
            receivedBlocks.removeValue(forKey: index)
            requestedBlocks.removeValue(forKey: index)
            inProgress.remove(index)
            return false
        }

        completed.set(index)
        inProgress.remove(index)
        pieceBuffers.removeValue(forKey: index)
        receivedBlocks.removeValue(forKey: index)
        requestedBlocks.removeValue(forKey: index)
        return true
    }

    /// Get the completed bitfield.
    public func getCompleted() -> Bitfield {
        completed
    }

    /// Check if a piece is complete.
    public func hasPiece(_ index: Int) -> Bool {
        completed.get(index)
    }

    /// Check if all pieces are complete.
    public func isComplete() -> Bool {
        completed.allSet
    }

    /// Get progress as a fraction.
    public func progress() -> Double {
        guard pieceCount > 0 else { return 1.0 }
        return Double(completed.popcount) / Double(pieceCount)
    }

    /// Expected size of a specific piece.
    public func expectedPieceSize(_ index: Int) -> Int {
        let start = Int64(index) * Int64(pieceLength)
        return Int(min(Int64(pieceLength), totalSize - start))
    }

    /// Get the assembled piece data buffer (before completion/verification).
    public func getPieceBuffer(_ index: Int) -> Data? {
        pieceBuffers[index]
    }

    /// Number of 16KB blocks in a piece.
    public func blockCount(for pieceIndex: Int) -> Int {
        let size = expectedPieceSize(pieceIndex)
        return (size + 16383) / 16384
    }

    /// Whether a piece is currently being downloaded.
    public func isInProgress(_ index: Int) -> Bool {
        inProgress.contains(index)
    }

    /// The standard piece length for this torrent.
    public func getPieceLength() -> Int {
        pieceLength
    }

    /// Total number of pieces.
    public func getPieceCount() -> Int {
        pieceCount
    }
}
