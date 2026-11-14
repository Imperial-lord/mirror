import SwiftUI

struct DesktopUpdatePanel: View {
  @Bindable var updates: DesktopUpdateService
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 14) {
        PhosphorView(updates.hasUpdate ? .downloadLinear : .rotateRight, size: 22)
          .frame(width: 44, height: 44).background(Color.mirrorSurface2, in: Circle())
        VStack(alignment: .leading, spacing: 6) {
          Text("App updates").font(.headline)
          Text(updates.status).font(.callout).foregroundStyle(Color.mirrorTextSecondary)
          Text("Installed version \(updates.currentVersion)").font(.caption)
            .foregroundStyle(Color.mirrorTextTertiary)
        }
        Spacer()
        if !updates.hasUpdate {
          Button("Check now") { updates.checkNow() }.buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .disabled(updates.busy || !updates.supportsInstallation)
        }
      }
      if updates.phase == .downloading {
        VStack(alignment: .leading, spacing: 9) {
          if let progress = updates.progress { ProgressView(value: progress).tint(Color.mirrorInk) }
          else { ProgressView().controlSize(.small) }
          HStack {
            Text(downloadSize).font(.caption).monospacedDigit().foregroundStyle(Color.mirrorTextSecondary)
            Spacer()
            Button("Cancel") { updates.cancelDownload() }.buttonStyle(.plain).font(.caption)
          }
        }
      } else if updates.phase == .preparing {
        ProgressView(value: updates.extractionProgress).tint(Color.mirrorInk)
        Text("Verifying and preparing the new version.").font(.caption).foregroundStyle(Color.mirrorTextSecondary)
      } else if updates.phase == .available {
        HStack(spacing: 18) {
          DesktopAction(title: "Download update", icon: .downloadLinear, primary: true) { updates.downloadUpdate() }
          if let url = updates.releaseURL {
            Link("What’s new", destination: url).font(.caption).foregroundStyle(Color.mirrorTextSecondary)
          }
        }
      } else if updates.phase == .ready {
        HStack(spacing: 18) {
          DesktopAction(title: "Restart and update", icon: .rotateRight, primary: true) { updates.restartAndInstall() }
          Text("Mirror will reopen. Your library and downloads stay in place.").font(.caption)
            .foregroundStyle(Color.mirrorTextSecondary)
        }
      } else if updates.phase == .failed {
        if let message = updates.message { Text(message).font(.caption).foregroundStyle(Color.mirrorTextSecondary) }
        Button("Try again") { updates.checkNow() }.buttonStyle(.plain).font(.callout)
      }
      if updates.supportsInstallation {
        Divider().overlay(Color.mirrorInk.opacity(0.1))
        Toggle(isOn: $updates.automaticChecks) {
          VStack(alignment: .leading, spacing: 5) {
            Text("Automatically check for updates").font(.callout)
            Text("Checks GitHub while Mirror is open. You choose when to download and restart.")
              .font(.caption).foregroundStyle(Color.mirrorTextTertiary)
          }
        }.toggleStyle(.switch).tint(Color.mirrorInk)
        if let date = updates.lastChecked {
          Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption).foregroundStyle(Color.mirrorTextTertiary)
        }
      } else {
        Text("In-app updates are enabled in the downloadable release build.")
          .font(.caption).foregroundStyle(Color.mirrorTextTertiary)
      }
    }.desktopPanel()
  }
  private var downloadSize: String {
    let downloaded = ByteCountFormatter.string(fromByteCount: Int64(clamping: updates.downloaded), countStyle: .file)
    guard updates.total > 0 else { return downloaded }
    return downloaded + " of " + ByteCountFormatter.string(fromByteCount: Int64(clamping: updates.total), countStyle: .file)
  }
}
