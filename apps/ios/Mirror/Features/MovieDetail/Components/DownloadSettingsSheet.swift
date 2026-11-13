import SwiftUI

struct DownloadSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = DownloadStore.shared
    @State private var selectedHash = ""
    @State private var subtitles: Set<String> = ["en"]
    @State private var error: String?
    let movie: MovieDetail
    private var choices: [Torrent] { MovieQuality.choices(movie.torrents ?? []) }
    private var existing: OfflineDownload? { store.records.first { $0.id == movie.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Color.clear.frame(width: 36, height: 36)
                Text("Download Settings").font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity)
                Button { dismiss() } label: {
                    PhosphorView(.close, size: 16, color: Color.mirrorInk).frame(width: 36, height: 36).background(Color.mirrorInk.opacity(0.08), in: Circle())
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(movie.title).font(.system(size: 16, weight: .medium))
                    Text("Quality").font(.system(size: 13)).foregroundStyle(Color.mirrorTextTertiary)
                    ForEach(choices) { torrent in
                        Button { selectedHash = torrent.hash } label: {
                            option(name: MovieQuality.label(torrent.quality), detail: torrent.size, selected: selectedHash == torrent.hash)
                        }.buttonStyle(.plain)
                    }
                    if choices.isEmpty { Text("No downloadable video is available for this movie.").font(.system(size: 14)) }
                    if let asset = existing?.asset, choices.first(where: { $0.hash == selectedHash })?.hash != asset.hash {
                        Text("This will replace your downloaded \(MovieQuality.label(asset.quality)) video. Your subtitles and watch position will be kept.")
                            .font(.system(size: 13)).foregroundStyle(Color.mirrorTextSecondary)
                    }
                    HStack {
                        Text("Audio")
                        Spacer()
                        Text("Original audio").foregroundStyle(Color.mirrorTextTertiary)
                    }.font(.system(size: 14)).padding(16).background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 12))
                    Text("Subtitles").font(.system(size: 13)).foregroundStyle(Color.mirrorTextTertiary)
                    Text("Choose any languages to keep offline, or leave all unselected. If a language is unavailable, we’ll try English.")
                        .font(.system(size: 13)).foregroundStyle(Color.mirrorTextSecondary)
                    ForEach(SubtitleLanguage.codes, id: \.self) { code in
                        Button {
                            if subtitles.contains(code) { subtitles.remove(code) } else { subtitles.insert(code) }
                        } label: {
                            option(name: SubtitleLanguage.name(code), detail: existing?.subtitles[code] != nil ? "Downloaded" : "", selected: subtitles.contains(code))
                        }.buttonStyle(.plain)
                    }
                    if let existing, !existing.subtitles.isEmpty {
                        Text("Previously downloaded subtitles stay available when you add another language.").font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
                    }
                }
            }
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(Color.mirrorInk.opacity(0.7)) }
            Button {
                guard let torrent = choices.first(where: { $0.hash == selectedHash }) else { return }
                do { try store.enqueue(movie: movie, torrent: torrent, languages: subtitles); dismiss() }
                catch { self.error = error.localizedDescription }
            } label: {
                Text(existing == nil ? "Download" : "Save download").font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 52).foregroundStyle(Color.mirrorOnInk).background(Color.mirrorInk, in: Capsule())
            }.disabled(selectedHash.isEmpty)
        }.padding(16).padding(.top, 12).padding(.bottom, 12).foregroundStyle(Color.mirrorInk).background(Color(mirrorHex: "121215")).tint(Color.mirrorInk)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .onAppear {
            store.start()
            selectedHash = choices.first(where: { $0.hash == existing?.torrent.hash })?.hash ?? choices.first?.hash ?? ""
            if let existing { subtitles = Set(existing.subtitles.keys) }
        }
    }
    private func option(name: String, detail: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(name).font(.system(size: 15))
            Spacer()
            Text(detail).font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
            ZStack {
                Circle().fill(selected ? Color.mirrorInk : .clear).overlay(Circle().stroke(Color.mirrorInk.opacity(0.3), lineWidth: selected ? 0 : 1.5))
                if selected { PhosphorView(.check, size: 12, color: Color.mirrorOnInk) }
            }.frame(width: 22, height: 22)
        }.padding(16).background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 12))
    }
}
