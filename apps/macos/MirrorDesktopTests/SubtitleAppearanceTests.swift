import AppKit
import SwiftUI
import XCTest
@testable import MirrorDesktop

@MainActor final class SubtitleAppearanceTests: XCTestCase {
  func testSettingsFitPopoverAndRenderInBothThemes() throws {
    for dark in [false, true] {
      let view = NSHostingView(rootView: SubtitleAppearanceSettings()
        .padding(23).frame(width: 350).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color.mirrorInk).background(Color.mirrorSurface1)
        .environment(\.colorScheme, dark ? .dark : .light))
      let size = view.fittingSize
      XCTAssertEqual(size.width, 350, accuracy: 1)
      XCTAssertLessThan(size.height, 550)
      let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      window.contentView = view
      window.displayIfNeeded()
      view.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let image = NSImage(size: size)
      image.addRepresentation(bitmap)
      let attachment = XCTAttachment(image: image)
      attachment.name = "Subtitle settings \(dark ? "dark" : "light")"
      attachment.lifetime = .keepAlways
      add(attachment)
      window.close()
    }
  }
}
