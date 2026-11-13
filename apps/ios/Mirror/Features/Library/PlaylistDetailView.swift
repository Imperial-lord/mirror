import SwiftUI

struct PlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = LibraryStore.shared
    let playlistID: String?
    @State private var adding = false
    @State private var renaming = false
    @State private var selecting = false
    @State private var selected: Set<Int> = []
    @State private var confirmingRemoval = false
    @State private var busy = false
    @State private var error: String?
    private var playlist: LibraryPlaylist? { store.playlists.first { $0.id == playlistID } }
    private var title: String { playlistID == nil ? "Favorites" : playlist?.name ?? "Playlist" }
    private var movies: [SavedMovie] { store.movies(playlistID: playlistID) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: {
                        PhosphorView(.caretLeft, size: 18, color: Color.mirrorInk).frame(width: 44, height: 44).background(Color(mirrorHex: "18181B"), in: Circle())
                    }
                    Text(title).font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity).lineLimit(1)
                    Button(selecting ? "Done" : "Select") { selecting.toggle(); selected = [] }
                        .font(.system(size: 13)).frame(width: 44).disabled(movies.isEmpty || busy)
                }
                HStack {
                    Text(movieCount(movies.count)).font(.system(size: 13)).foregroundStyle(Color.mirrorTextTertiary)
                    Spacer()
                    if playlistID != nil {
                        Button("Rename") { renaming = true }.font(.system(size: 13))
                        Button { adding = true } label: {
                            HStack(spacing: 4) { PhosphorView(.add, size: 14, color: Color.mirrorInk); Text("Add movies").font(.system(size: 13)) }
                                .padding(8).background(Color.mirrorInk.opacity(0.08), in: Capsule())
                        }
                    }
                }
                if let failure = store.error {
                    Text(failure).font(.system(size: 13))
                    Button("Try again") { store.retry() }
                }
                ScrollView {
                    if !store.loaded && store.error == nil { ProgressView().tint(Color.mirrorInk).padding(40) }
                    else if movies.isEmpty {
                        VStack(spacing: 12) {
                            PhosphorView(playlistID == nil ? .bookmarkLinear : .folder, size: 36, color: Color.mirrorInk.opacity(0.4))
                            Text(playlistID == nil ? "No saved movies yet" : "This playlist is empty").font(.system(size: 17, weight: .medium))
                            Text(playlistID == nil ? "Save a movie from its detail page to add it to Favorites." : "Add movies from Favorites, or choose this folder when saving a movie.")
                                .font(.system(size: 14)).foregroundStyle(Color.mirrorTextTertiary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], alignment: .leading, spacing: 20) {
                            ForEach(movies) { movie in
                                Group {
                                    if selecting {
                                        Button { if selected.contains(movie.id) { selected.remove(movie.id) } else { selected.insert(movie.id) } } label: {
                                            SavedMovieCard(movie: movie, width: (geometry.size.width - 44) / 2)
                                                .overlay(alignment: .topTrailing) {
                                                    LibrarySelectionIndicator(selected: selected.contains(movie.id))
                                                        .padding(8).background(.black.opacity(0.5), in: Circle()).padding(6)
                                                }
                                        }.buttonStyle(.plain)
                                    } else {
                                        NavigationLink(value: LibraryDestination.movie(movie.id)) {
                                            SavedMovieCard(movie: movie, width: (geometry.size.width - 44) / 2)
                                        }.buttonStyle(.plain)
                                        .contextMenu {
                                            Button(playlistID == nil ? "Remove from Favorites" : "Remove from playlist", role: .destructive) {
                                                selected = [movie.id]; confirmingRemoval = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.padding(.bottom, 110)
            }.padding(.horizontal, 16).padding(.top, 4)
        }
        .background(Color(mirrorHex: "060606").ignoresSafeArea()).foregroundStyle(Color.mirrorInk).tint(Color.mirrorInk).navigationBarHidden(true)
        .task { store.start() }
        .sheet(isPresented: $adding) { PlaylistMoviesSheet(playlistID: playlistID ?? "") }
        .sheet(isPresented: $renaming) { PlaylistNameSheet(initialName: title) { if let playlistID { try await store.rename(id: playlistID, name: $0) } } }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                Button { confirmingRemoval = true } label: {
                    Text(busy ? "Removing…" : "Remove selected (\(selected.count))").font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity).padding(14).foregroundStyle(Color.mirrorOnInk).background(Color.mirrorInk, in: Capsule())
                }.disabled(selected.isEmpty || busy).padding(16).padding(.bottom, 70).background(Color(mirrorHex: "000000"))
            }
        }
        .alert(playlistID == nil ? "Remove from Favorites?" : "Remove from playlist?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                busy = true
                let items = movies.filter { selected.contains($0.id) }
                Task { @MainActor in
                    do { for movie in items { try await store.remove(movie: movie, from: playlistID) }; selected = []; selecting = false }
                    catch { self.error = error.localizedDescription }
                    busy = false
                }
            }
        } message: {
            Text(playlistID == nil ? "These movies will also be removed from your custom playlists." : "These movies will stay in Favorites.")
        }
        .alert("Couldn’t update playlist", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct PlaylistMoviesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = LibraryStore.shared
    let playlistID: String
    @State private var selected: Set<Int> = []
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if store.favorites.isEmpty {
                    Text("Save movies to Favorites first, then add them to this playlist.").font(.system(size: 14)).foregroundStyle(Color.mirrorTextSecondary).padding(24)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.favorites) { movie in
                            Button {
                                if selected.contains(movie.id) { selected.remove(movie.id) } else { selected.insert(movie.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(movie.title).font(.system(size: 15, weight: .medium))
                                        Text(movie.subtitle).font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
                                    }
                                    Spacer()
                                    LibrarySelectionIndicator(selected: selected.contains(movie.id))
                                }.padding(16).background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16)
                }
                if let error { Text(error).font(.system(size: 13)).padding(.horizontal, 16) }
                Button {
                    busy = true; error = nil
                    Task { @MainActor in
                        do { try await store.setMovies(playlistID: playlistID, movieIDs: selected); dismiss() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                } label: {
                    Text(busy ? "Saving…" : "Save").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 52)
                        .foregroundStyle(Color.mirrorOnInk).background(Color.mirrorInk, in: Capsule())
                }.disabled(busy).padding(16)
            }.background(Color(mirrorHex: "121215")).foregroundStyle(Color.mirrorInk).navigationTitle("Add movies").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        }.tint(Color.mirrorInk).interactiveDismissDisabled(busy)
        .onAppear { selected = Set(store.playlists.first { $0.id == playlistID }?.movieIds ?? []) }
    }
}

private struct LibrarySelectionIndicator: View {
    let selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(selected ? Color.mirrorInk : Color.clear)
                .overlay(Circle().stroke(Color.mirrorInk.opacity(0.5), lineWidth: selected ? 0 : 1.5))
            if selected { PhosphorView(.check, size: 13, color: Color.mirrorOnInk) }
        }.frame(width: 24, height: 24)
    }
}
