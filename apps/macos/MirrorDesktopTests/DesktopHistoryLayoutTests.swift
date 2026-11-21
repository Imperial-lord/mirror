import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import MirrorDesktop

@MainActor final class DesktopHistoryLayoutTests: XCTestCase {
  func testPlaylistCardsKeepTheirTitleAndMenuInOneCompactRow() throws {
    for dark in [false, true] {
      let card = DesktopPlaylistCard(
        name: "A long playlist name that should truncate cleanly", movieCount: 3,
        artwork: nil, open: {}
      ) {
        Button("Edit movies") {}
        Button("Rename") {}
        Button("Delete playlist", role: .destructive) {}
      }
      .frame(width: 235).fixedSize(horizontal: false, vertical: true)
      .environment(\.colorScheme, dark ? .dark : .light)
      .foregroundStyle(Color.mirrorInk).background(Color.mirrorBackground)
      let view = NSHostingView(rootView: card)
      view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      let size = view.fittingSize
      XCTAssertEqual(size.width, 235, accuracy: 1)
      XCTAssertLessThan(size.height, 215)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = view.appearance
      window.contentView = view
      defer { window.close() }
      window.displayIfNeeded()
      view.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let image = NSImage(size: view.bounds.size)
      image.addRepresentation(bitmap)
      let attachment = XCTAttachment(image: image)
      attachment.name = dark ? "Playlist card dark" : "Playlist card light"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  func testHistoryCardsStayCompactInBothAppearances() throws {
    let container = try ModelContainer(
      for: WatchHistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let item = WatchHistoryItem(
      movieId: 1, title: "A movie with a long title", posterURL: nil, runtime: 100,
      progressSeconds: 60, userId: "layout-test")
    for dark in [false, true] {
      for watched in [false, true] {
        let card = Group {
          if watched { DesktopHistoryPoster(item: item) }
          else { DesktopHistoryContinueCard(item: item) }
        }
        .frame(width: 260).fixedSize(horizontal: false, vertical: true)
        .environment(DesktopSession()).modelContainer(container)
        .environment(\.colorScheme, dark ? .dark : .light)
        .foregroundStyle(Color.mirrorInk).background(Color.mirrorBackground)
        let view = NSHostingView(rootView: card)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = view.fittingSize
        XCTAssertEqual(size.width, 260, accuracy: 1)
        XCTAssertLessThan(size.height, watched ? 460 : 220,
          "History menu must not stretch the card or squeeze out its title (dark: \(dark))")
        let window = NSWindow(
          contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = view.appearance
        window.contentView = view
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = "History \(watched ? "watched" : "continuing") \(dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.close()
      }
    }
  }

  func testHistoryMenuHasBoundedNativeControlSize() throws {
    let container = try ModelContainer(
      for: WatchHistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    for dark in [false, true] {
      let menu = WatchHistoryMenu(movieId: 1, title: "Movie", userId: "layout-test", watched: false)
        .modelContainer(container).environment(\.colorScheme, dark ? .dark : .light)
      let view = NSHostingView(rootView: menu)
      view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      XCTAssertLessThanOrEqual(view.fittingSize.width, 32)
      XCTAssertLessThanOrEqual(view.fittingSize.height, 32)
    }
  }

  func testMenuRemainsVisibleOnLightAndDarkBackgrounds() throws {
    let container = try ModelContainer(
      for: WatchHistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    for dark in [false, true] {
      let background = dark ? Color.black : Color.white
      let content = WatchHistoryMenu(
        movieId: 1, title: "Movie", userId: "layout-test", watched: false)
        .frame(width: 44, height: 44).background(background)
        .modelContainer(container).environment(\.colorScheme, dark ? .dark : .light)
      let host = NSHostingView(rootView: content)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 44, height: 44), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      window.contentView = host
      window.displayIfNeeded()
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      var visiblePixels = 0
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
          let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
          if dark ? brightness > 0.2 : brightness < 0.8 { visiblePixels += 1 }
        }
      }
      let image = NSImage(size: host.bounds.size)
      image.addRepresentation(bitmap)
      let attachment = XCTAttachment(image: image)
      attachment.name = dark ? "History menu – dark" : "History menu – light"
      attachment.lifetime = .keepAlways
      add(attachment)
      window.close()
      XCTAssertGreaterThan(visiblePixels, 10, "Menu dots must contrast with the background")
    }
  }
}
