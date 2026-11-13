import Foundation
import NIOCore

/// Coordinates multiple trackers with tier support.
public actor TrackerManager {
    public static let defaultTrackers = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.demonii.com:1337/announce",
        "udp://tracker.openbittorrent.com:80/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce"
    ]

    private let tiers: [[String]]
    private let group: EventLoopGroup
    private var lastResponse: AnnounceResponse?
    private var announceInterval: Int = 1800

    public init(tiers: [[String]], group: EventLoopGroup) {
        var allTiers = tiers
        allTiers.insert(Self.defaultTrackers, at: 0)
        self.tiers = allTiers
        self.group = group
    }

    /// Convenience: create from TorrentInfo.
    public init(info: TorrentInfo, group: EventLoopGroup) {
        var tiers = info.announceList
        if tiers.isEmpty, let url = info.announceURL {
            tiers = [[url]]
        }
        tiers.insert(Self.defaultTrackers, at: 0)
        self.tiers = tiers
        self.group = group
    }

    /// Announce to tracker tiers, aggregating live peers from active trackers.
    public func announce(params: AnnounceParams) async throws -> AnnounceResponse {
        var allPeers: [(String, UInt16)] = []
        var bestSeeders = 0
        var bestLeechers = 0
        var interval = 1800

        for tier in tiers {
            for urlString in tier {
                do {
                    let response: AnnounceResponse
                    if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                        let tracker = HTTPTracker(announceURL: urlString)
                        response = try await tracker.announce(params: params)
                    } else if urlString.hasPrefix("udp://") {
                        guard let components = URLComponents(string: urlString),
                              let host = components.host,
                              let port = components.port else {
                            continue
                        }
                        let tracker = UDPTracker(host: host, port: port, group: group)
                        response = try await tracker.announce(params: params)
                    } else {
                        continue
                    }

                    print("[SwiftTorrent] Tracker \(urlString): \(response.peers.count) peers")
                    allPeers.append(contentsOf: response.peers)
                    bestSeeders = max(bestSeeders, response.seeders)
                    bestLeechers = max(bestLeechers, response.leechers)
                    interval = response.interval
                    if allPeers.count >= 40 {
                        let merged = AnnounceResponse(interval: interval, seeders: bestSeeders, leechers: bestLeechers, peers: allPeers)
                        lastResponse = merged
                        announceInterval = interval
                        return merged
                    }
                } catch {
                    continue // Try next tracker in tier
                }
            }
        }

        if !allPeers.isEmpty {
            let merged = AnnounceResponse(interval: interval, seeders: bestSeeders, leechers: bestLeechers, peers: allPeers)
            lastResponse = merged
            announceInterval = interval
            return merged
        }

        throw TrackerError.connectionFailed
    }

    public func getInterval() -> Int {
        announceInterval
    }
}
