import SwiftUI
import NukeUI

enum LibraryDestination: Hashable {
    case playlist(String?)
    case movie(Int)
}

struct FavoritesLibraryContent: View {
    @State private var store = LibraryStore.shared
    @State private var creating = false
    @State private var renaming: LibraryPlaylist?
    @State private var deleting: LibraryPlaylist?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let failure = store.error {
                Text(failure).font(.system(size: 13)).padding(.horizontal, 16)
                Button("Try again") { store.retry() }.padding(.horizontal, 16)
            }
            if !store.loaded && store.error == nil { ProgressView().tint(Color.mirrorInk).frame(maxWidth: .infinity) }
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: LibraryDestination.playlist(nil)) {
                    HStack {
                        Text("Favorites").font(.system(size: 17, weight: .semibold))
                        Spacer(); PhosphorView(.caretRight, size: 14, color: Color.mirrorTextTertiary)
                    }
                }.buttonStyle(.plain).padding(.horizontal, 16)
                if store.loaded && store.favorites.isEmpty {
                    Text("Save movies to keep them here and organize them into playlists.")
                        .font(.system(size: 14)).foregroundStyle(Color.mirrorTextTertiary).padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(store.favorites.prefix(10)) { movie in
                                NavigationLink(value: LibraryDestination.movie(movie.id)) {
                                    SavedMovieCard(movie: movie, width: 125)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 16)
                    }
                }
            }
            HStack {
                Text("My playlists").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { creating = true } label: {
                    HStack(spacing: 4) { PhosphorView(.add, size: 14, color: Color.mirrorInk); Text("Add New").font(.system(size: 13, weight: .medium)) }
                        .padding(.horizontal, 12).padding(.vertical, 8).background(Color.mirrorInk.opacity(0.08), in: Capsule())
                }.disabled(!store.loaded)
            }.padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(store.playlists) { playlist in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink(value: LibraryDestination.playlist(playlist.id)) {
                            PhosphorView(.folder, size: 36, color: Color.mirrorInk.opacity(0.4))
                                .frame(maxWidth: .infinity).frame(height: 110)
                                .background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                        HStack(alignment: .top) {
                            NavigationLink(value: LibraryDestination.playlist(playlist.id)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                    Text(movieCount(store.movies(playlistID: playlist.id).count)).font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Menu {
                                Button("Rename") { renaming = playlist }
                                Button("Delete playlist", role: .destructive) { deleting = playlist }
                            } label: { PhosphorView(.more, size: 16, color: Color.mirrorTextSecondary).frame(width: 32, height: 32) }
                        }
                    }
                }
            }.padding(.horizontal, 16)
        }
        .foregroundStyle(Color.mirrorInk).tint(Color.mirrorInk)
        .task { store.start() }
        .sheet(isPresented: $creating) { PlaylistNameSheet { _ = try await store.create(name: $0) } }
        .sheet(item: $renaming) { playlist in PlaylistNameSheet(initialName: playlist.name) { try await store.rename(id: playlist.id, name: $0) } }
        .alert("Delete playlist?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                guard let id = deleting?.id else { return }
                Task { do { try await store.delete(id: id) } catch { self.error = error.localizedDescription } }
                deleting = nil
            }
        } message: { Text("The movies will stay in Favorites.") }
        .alert("Couldn’t update library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

func movieCount(_ count: Int) -> String { count == 0 ? "Empty" : "\(count) \(count == 1 ? "movie" : "movies")" }

struct SavedMovieCard: View {
    let movie: SavedMovie
    let width: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyImage(url: URL(string: movie.poster)) { state in
                if let image = state.image { image.resizable().scaledToFill() }
                else { Color(mirrorHex: "18181B") }
            }.frame(width: width, height: width * 1.5).clipShape(RoundedRectangle(cornerRadius: 14))
            Text(movie.title).font(.system(size: width > 140 ? 14 : 13, weight: .medium)).lineLimit(width > 140 ? 2 : 1)
            Text(movie.subtitle).font(.system(size: 11)).foregroundStyle(Color.mirrorTextTertiary).lineLimit(1)
        }.frame(width: width, alignment: .leading).foregroundStyle(Color.mirrorInk)
    }
}

struct PlaylistNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialName = ""
    var onSave: (String) async throws -> Void
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(initialName.isEmpty ? "Give your playlist name" : "Rename playlist").font(.system(size: 18, weight: .semibold))
                Spacer(); Button("Cancel") { dismiss() }.disabled(busy).font(.system(size: 14))
            }
            TextField("Playlist name", text: $name).font(.system(size: 15)).padding(14)
                .background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 12)).submitLabel(.done)
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(Color.mirrorTextSecondary) }
            Spacer(minLength: 0)
            Button {
                busy = true; error = nil
                Task { @MainActor in
                    do { try await onSave(name); dismiss() } catch { self.error = error.localizedDescription }
                    busy = false
                }
            } label: {
                Group { if busy { ProgressView().tint(Color.mirrorOnInk) } else { Text("Save").font(.system(size: 16, weight: .semibold)) } }
                    .frame(maxWidth: .infinity).frame(height: 52).foregroundStyle(Color.mirrorOnInk).background(Color.mirrorInk, in: Capsule())
            }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(20).padding(.top, 12).foregroundStyle(Color.mirrorInk).background(Color(mirrorHex: "121215")).tint(Color.mirrorInk)
        .presentationDetents([.height(300)]).presentationDragIndicator(.visible).interactiveDismissDisabled(busy)
        .onAppear { name = initialName }
    }
}
