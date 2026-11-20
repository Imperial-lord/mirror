import SwiftData
import SwiftUI

struct WatchHistoryMenu: View {
  let movieId: Int
  let title: String
  let userId: String
  let watched: Bool
  var onInformation: (() -> Void)? = nil
  @Environment(\.modelContext) private var context
  @State private var confirming = false
  @State private var removing = false
  @State private var failed = false

  private var listName: String { watched ? "Watched" : "Continue Watching" }
  var body: some View {
    Menu {
      if let onInformation { Button("Movie information", action: onInformation) }
      Button("Remove from \(listName)", role: .destructive) { confirming = true }
    } label: {
      Group {
        if removing {
          ProgressView().controlSize(.small)
        } else {
          PhosphorView(.more, size: 16, color: .mirrorTextSecondary)
        }
      }.frame(width: 28, height: 28).contentShape(Rectangle())
    }
    #if os(macOS)
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
    #endif
    .fixedSize()
    .disabled(removing)
    .tint(Color.mirrorInk)
    .accessibilityLabel(removing ? "Removing \(title)" : "More options for \(title)")
    .alert("Remove from \(listName)?", isPresented: $confirming) {
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) {
        removing = true
        Task { @MainActor in
          defer { removing = false }
          do {
            try await WatchHistorySync.remove(movieId: movieId, userId: userId, context: context)
          } catch { failed = true }
        }
      }
    } message: {
      Text(
        "This permanently deletes the watch history and saved position for “\(title)” from your account and this device. This can’t be undone."
      )
    }
    .alert("Couldn’t remove movie", isPresented: $failed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Check your connection and available storage, then try again.")
    }
  }
}
