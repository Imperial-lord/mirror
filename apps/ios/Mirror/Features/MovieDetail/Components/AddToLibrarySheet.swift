import SwiftUI

struct AddToLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = LibraryStore.shared
    @State private var selection = LibrarySelection()
    @State private var initialized = false
    @State private var creating = false
    @State private var busy = false
    @State private var error: String?
    let movie: SavedMovie

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Color.clear.frame(width: 36, height: 36)
                Text("Add to Library").font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity)
                Button { dismiss() } label: {
                    PhosphorView(.close, size: 16, color: Color.mirrorInk).frame(width: 36, height: 36).background(Color.mirrorInk.opacity(0.08), in: Circle())
                }
            }
            ScrollView {
                VStack(spacing: 24) {
                    selectionRow(name: "Favorites", subtitle: "All saved movies", icon: .bookmarkBold, selected: selection.favorite) {
                        selection.toggleFavorite()
                    }
                    HStack {
                        Text("My playlists").font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button { creating = true } label: { Label { Text("Add New") } icon: { PhosphorView(.add, size: 14, color: Color.mirrorInk) } }
                            .font(.system(size: 13)).padding(8).background(Color.mirrorInk.opacity(0.08), in: Capsule())
                    }
                    if !store.loaded { ProgressView().tint(Color.mirrorInk) }
                    ForEach(store.playlists) { playlist in
                        selectionRow(name: playlist.name, subtitle: "Custom playlist", icon: .folder, selected: selection.playlists.contains(playlist.id)) {
                            selection.togglePlaylist(playlist.id)
                        }
                    }
                    if let failure = store.error {
                        Text(failure).font(.system(size: 13)).foregroundStyle(.secondary)
                        Button("Try again") { store.retry() }
                    }
                }
            }
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(Color.mirrorInk.opacity(0.7)) }
            Button {
                busy = true; error = nil
                Task { @MainActor in
                    do { try await store.save(movie: movie, favorite: selection.favorite, selections: selection.playlists); dismiss() }
                    catch { self.error = error.localizedDescription }
                    busy = false
                }
            } label: {
                Group { if busy { ProgressView().tint(Color.mirrorOnInk) } else { Text("Save").font(.system(size: 16, weight: .semibold)) } }
                    .frame(maxWidth: .infinity).frame(height: 52).foregroundStyle(Color.mirrorOnInk).background(Color.mirrorInk, in: Capsule())
            }.disabled(busy || !initialized || store.error != nil)
        }
        .padding(16).padding(.top, 12).padding(.bottom, 12)
        .foregroundStyle(Color.mirrorInk).background(Color(mirrorHex: "121215")).tint(Color.mirrorInk)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
        .sheet(isPresented: $creating) { PlaylistNameSheet { name in
            let id = try await store.create(name: name); selection.addPlaylist(id)
        } }
        .task { store.start(); initialize() }
        .onChange(of: store.loaded) { _, _ in initialize() }
        .onChange(of: store.accountID) { _, _ in initialized = false; selection = LibrarySelection(); initialize() }
    }
    private func initialize() {
        guard store.loaded, !initialized else { return }
        selection = LibrarySelection(playlists: store.memberships(movieID: movie.id))
        initialized = true
    }
    private func selectionRow(name: String, subtitle: String, icon: PhosphorIcon, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                PhosphorView(icon, size: 24, color: Color.mirrorInk.opacity(0.7)).frame(width: 44, height: 44).background(Color.mirrorInk.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 16, weight: .medium))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.mirrorTextTertiary)
                }
                Spacer()
                ZStack {
                    Circle().fill(selected ? Color.mirrorInk : .clear).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.mirrorInk.opacity(0.3), lineWidth: selected ? 0 : 1.5))
                    if selected { PhosphorView(.check, size: 12, color: Color.mirrorOnInk) }
                }
            }.padding(14).background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(busy || !initialized)
    }
}
