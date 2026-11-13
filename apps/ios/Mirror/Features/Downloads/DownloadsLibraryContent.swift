import SwiftUI
import NukeUI

struct DownloadsLibraryContent: View {
    @State private var store = DownloadStore.shared
    @State private var playbackRequestedAt = ContinuousClock.now
    @State private var playing: OfflineMovie?
    @State private var editing: OfflineDownload?
    @State private var deleting: OfflineDownload?
    @State private var error: String?
    private var pending: [OfflineDownload] { store.records.filter { $0.status != .completed } }
    private var complete: [OfflineDownload] { store.records.filter { $0.status == .completed } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let error = store.error {
                Text(error).font(.system(size: 13)).foregroundStyle(Color.mirrorTextSecondary)
            }
            if store.records.isEmpty {
                VStack(spacing: 12) {
                    PhosphorView(.downloadLinear, size: 36, color: Color.mirrorTextTertiary)
                    Text("No downloads yet").font(.system(size: 17, weight: .medium))
                    Text("Download a movie to watch it here without an internet connection.")
                        .font(.system(size: 14)).foregroundStyle(Color.mirrorTextTertiary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 50)
            }
            if !pending.isEmpty {
                sectionTitle("Downloading")
                VStack(spacing: 10) { ForEach(pending) { row($0) } }
            }
            if !complete.isEmpty {
                sectionTitle("Downloaded")
                VStack(spacing: 10) { ForEach(complete) { row($0) } }
            }
        }.padding(.horizontal, 16).foregroundStyle(Color.mirrorInk).tint(Color.mirrorInk)
        .task { store.start() }
        .sheet(item: $editing) { DownloadSettingsSheet(movie: $0.movie) }
        .fullScreenCover(item: $playing) { MirrorVideoPlayerView(download: $0, requestedAt: playbackRequestedAt) }
        .alert("Delete download?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let record = deleting { do { try store.delete(record.id) } catch { self.error = error.localizedDescription } }
                deleting = nil
            }
        } message: { Text("The video and its subtitles will be removed from this device. Your watch history will be kept.") }
        .alert("Download unavailable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.mirrorTextTertiary)
    }
    private func row(_ record: OfflineDownload) -> some View {
        HStack(spacing: 12) {
            Group {
                if record.status == .completed {
                    Button {
                        do { playbackRequestedAt = .now; playing = try store.playback(record) } catch { self.error = error.localizedDescription }
                    } label: { downloadLabel(record) }.buttonStyle(.plain)
                } else { downloadLabel(record) }
            }

            Menu {
                if let asset = record.asset {
                    Button("Play downloaded \(MovieQuality.label(asset.quality))") { do { playbackRequestedAt = .now; playing = try store.playback(record) } catch { self.error = error.localizedDescription } }
                }
                if [.queued, .preparing, .downloading].contains(record.status) { Button("Pause") { store.pause(record.id) } }
                if [.paused, .failed].contains(record.status) { Button(record.status == .failed ? "Retry" : "Resume") { store.resume(record.id) } }
                Button("Download settings") { editing = record }
                Button("Delete download", role: .destructive) { deleting = record }
            } label: {
                if [.preparing, .downloading].contains(record.status) {
                    ZStack {
                        Circle().stroke(Color.mirrorInk.opacity(0.15), lineWidth: 2)
                        Circle().trim(from: 0, to: progress(record)).stroke(Color.mirrorInk, lineWidth: 2).rotationEffect(.degrees(-90))
                    }.frame(width: 24, height: 24).padding(10)
                } else { PhosphorView(record.status == .failed ? .warningCircle : .more, size: 22, color: Color.mirrorTextSecondary).frame(width: 44, height: 44) }
            }.accessibilityLabel("Options for \(record.movie.title)")
        }.padding(12).background(Color(mirrorHex: "121215"), in: RoundedRectangle(cornerRadius: 14))
    }
    private func downloadLabel(_ record: OfflineDownload) -> some View {
        HStack(spacing: 12) {
            poster(record).frame(width: 80, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(record.movie.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text("\(record.quality) • \(record.size)").font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
                Text(status(record)).font(.system(size: 11)).foregroundStyle(record.status == .failed ? Color(mirrorHex: "EF4444") : Color.mirrorTextSecondary).lineLimit(2)
                if let notice = record.notices.last { Text(notice).font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary).lineLimit(3) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(Rectangle())
    }
    @ViewBuilder
    private func poster(_ record: OfflineDownload) -> some View {
        if let url = store.poster(record), url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            LazyImage(url: store.poster(record)) { state in
                if let image = state.image { image.resizable().scaledToFill() }
                else { PhosphorView(.film, size: 24, color: Color.mirrorInk.opacity(0.5)).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(mirrorHex: "18181B")) }
            }
        }
    }
    private func progress(_ record: OfflineDownload) -> Double {
        let live = record.status == .downloading ? store.liveBytes : 0
        return record.total > 0 ? min(1, Double(record.bytes + live) / Double(record.total)) : 0
    }
    private func status(_ record: OfflineDownload) -> String {
        switch record.status {
        case .queued: return "Queued"
        case .preparing: return "Preparing download…"
        case .downloading: return "Downloading \(Int(progress(record) * 100))%"
        case .paused: return "Paused • \(Int(record.progress * 100))%"
        case .failed: return record.failure ?? "Download failed"
        case .completed:
            if record.duration > 0, record.position / record.duration > 0.95 { return "Watched • Available offline" }
            return record.position > 0 ? "Continue watching • Available offline" : "Available offline"
        }
    }
}
