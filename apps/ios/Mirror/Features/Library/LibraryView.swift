import SwiftUI
import NukeUI

public enum LibrarySegment: String, CaseIterable {
    case recent = "Recent"
    case favorites = "Favorites"
    case downloads = "Downloads"
}

public struct LibraryView: View {
    @State private var selectedSegment: LibrarySegment = .recent
    public init() {}

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 16) {
                // Centered Screen Header: Library (Behance Board 15)
                Text("Library")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.mirrorInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xs)

                // 3-Segment Switcher (Recent | Favorites | Downloads)
                HStack(spacing: 4) {
                    ForEach(LibrarySegment.allCases, id: \.self) { segment in
                        let isSelected = selectedSegment == segment
                        Button(action: {
                            HapticManager.shared.selection()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSegment = segment
                            }
                        }) {
                            Text(segment.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isSelected ? Color.mirrorInk : Color.mirrorTextTertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(isSelected ? Color(mirrorHex: "222226") : Color.clear)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(4)
                .background(Color(mirrorHex: "121215"))
                .clipShape(Capsule())
                .padding(.horizontal, Spacing.md)

                // Recent owns its refreshable history scroll; the other tabs are unchanged.
                if selectedSegment == .recent {
                    recentSection
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            if selectedSegment == .favorites { FavoritesLibraryContent() }
                            else { DownloadsLibraryContent() }
                        }.padding(.bottom, 110)
                    }
                }
            }
        }
        .tint(Color.mirrorInk)
        .navigationDestination(for: LibraryDestination.self) { destination in
            switch destination {
            case .playlist(let id): PlaylistDetailView(playlistID: id)
            case .movie(let id): MovieDetailView(movieId: id)
            }
        }
    }


    private var recentSection: some View { RecentLibraryContent() }

}
