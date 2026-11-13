import Foundation

/// Sequential and rarest-first piece selection strategy for torrent streaming.
public struct PiecePicker: Sendable {
    private let pieceCount: Int
    private var availability: [Int]  // how many peers have each piece
    private var priorityPieces: [Int] = []
    public mutating func prioritize(_ indices: [Int]) { priorityPieces = indices.filter { $0 >= 0 && $0 < pieceCount } }

    public var sequential: Bool = true

    public init(pieceCount: Int, sequential: Bool = true) {
        self.pieceCount = pieceCount
        self.availability = [Int](repeating: 0, count: pieceCount)
        self.sequential = sequential
    }

    /// Update availability from a peer's bitfield.
    public mutating func addPeerBitfield(_ bitfield: Bitfield) {
        for i in 0..<min(pieceCount, bitfield.count) {
            if bitfield.get(i) {
                availability[i] += 1
            }
        }
    }

    /// Remove a peer's bitfield from availability counts.
    public mutating func removePeerBitfield(_ bitfield: Bitfield) {
        for i in 0..<min(pieceCount, bitfield.count) {
            if bitfield.get(i) {
                availability[i] = max(0, availability[i] - 1)
            }
        }
    }

    /// Increment availability for a single piece (peer sent "have").
    public mutating func addHave(_ pieceIndex: Int) {
        guard pieceIndex >= 0 && pieceIndex < pieceCount else { return }
        availability[pieceIndex] += 1
    }

    /// Pick the next piece to request.
    /// In sequential mode: prioritizes piece 0 (start), the final piece (moov atom), then pieces 1..<pieceCount.
    public func pick(have: Bitfield, peerHas: Bitfield) -> Int? {
        for index in priorityPieces where !have.get(index) && peerHas.get(index) { return index }
        if sequential {
            // 1. Piece 0 (stream header)
            if pieceCount > 0 && !have.get(0) && peerHas.get(0) {
                return 0
            }
            // 2. Last piece (for MP4 trailing moov box)
            if pieceCount > 1 && !have.get(pieceCount - 1) && peerHas.get(pieceCount - 1) {
                return pieceCount - 1
            }
            // 3. Sequential from start to end
            for i in 1..<pieceCount {
                if !have.get(i) && peerHas.get(i) {
                    return i
                }
            }
            return nil
        }

        var best: Int?
        var bestAvail = Int.max

        for i in 0..<pieceCount {
            if !have.get(i) && peerHas.get(i) {
                if availability[i] < bestAvail {
                    bestAvail = availability[i]
                    best = i
                }
            }
        }

        return best
    }

    /// Pick multiple pieces (for pipelining).
    public func pickMultiple(have: Bitfield, peerHas: Bitfield, count: Int) -> [Int] {
        if sequential {
            var result: [Int] = []
            if pieceCount > 0 && !have.get(0) && peerHas.get(0) {
                result.append(0)
            }
            if pieceCount > 1 && !have.get(pieceCount - 1) && peerHas.get(pieceCount - 1) && !result.contains(pieceCount - 1) {
                result.append(pieceCount - 1)
            }
            for i in 1..<pieceCount {
                if result.count >= count { break }
                if !have.get(i) && peerHas.get(i) && !result.contains(i) {
                    result.append(i)
                }
            }
            return result
        }

        var candidates: [(index: Int, avail: Int)] = []
        for i in 0..<pieceCount {
            if !have.get(i) && peerHas.get(i) {
                candidates.append((i, availability[i]))
            }
        }
        candidates.sort { $0.avail < $1.avail }
        return Array(candidates.prefix(count).map(\.index))
    }
}
