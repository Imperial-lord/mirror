import AppKit
import XCTest

@testable import MirrorDesktop

@MainActor
final class DesktopWindowInteractionTests: XCTestCase {
  private final class Window: NSWindow {
    var fullscreenRequests = 0
    override func toggleFullScreen(_ sender: Any?) { fullscreenRequests += 1 }
  }

  private func window() -> Window {
    let window = Window(
      contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    return window
  }

  private func event(
    in window: NSWindow, type: NSEvent.EventType = .leftMouseDown,
    clicks: Int = 2, point: NSPoint? = nil
  ) -> NSEvent {
    NSEvent.mouseEvent(
      with: type, location: point ?? NSPoint(x: 400, y: window.frame.height - 6),
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
  }

  func testDoubleClickTogglesBothWaysAndConsumesRelease() {
    let window = window()
    let interaction = DesktopWindowInteraction()
    interaction.attach(to: window)
    defer { interaction.detach(); window.close() }
    let originalFrame = window.frame
    XCTAssertNil(interaction.handle(event(in: window)))
    XCTAssertEqual(window.fullscreenRequests, 1)
    XCTAssertNil(interaction.handle(event(in: window, type: .leftMouseUp)))
    NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
    XCTAssertNil(interaction.handle(event(in: window)))
    XCTAssertEqual(window.fullscreenRequests, 2)
    XCTAssertEqual(window.frame, originalFrame, "Leave sizing and restoration to native fullscreen")
  }

  func testSingleClickAndContentClicksPassThrough() {
    let window = window()
    let interaction = DesktopWindowInteraction()
    interaction.attach(to: window)
    defer { interaction.detach(); window.close() }
    let single = event(in: window, clicks: 1)
    XCTAssertTrue(interaction.handle(single) === single)
    let release = event(in: window, type: .leftMouseUp, clicks: 1)
    XCTAssertTrue(interaction.handle(release) === release)
    let content = event(in: window, point: NSPoint(x: 400, y: 200))
    XCTAssertTrue(interaction.handle(content) === content)
    XCTAssertEqual(window.fullscreenRequests, 0)
  }

  func testTrafficLightsRemainUsable() throws {
    let window = window()
    let interaction = DesktopWindowInteraction()
    interaction.attach(to: window)
    defer { interaction.detach(); window.close() }
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      let button = try XCTUnwrap(window.standardWindowButton(type))
      let bounds = button.convert(button.bounds, to: nil)
      let click = event(in: window, point: NSPoint(x: bounds.midX, y: bounds.midY))
      XCTAssertTrue(interaction.handle(click) === click)
    }
    XCTAssertEqual(window.fullscreenRequests, 0)
  }

  func testTopBarControlsAreNotIntercepted() throws {
    let window = window()
    let content = try XCTUnwrap(window.contentView)
    let button = NSButton(
      frame: NSRect(x: 380, y: content.bounds.height - 20, width: 80, height: 20))
    content.addSubview(button)
    let interaction = DesktopWindowInteraction()
    interaction.attach(to: window)
    defer { interaction.detach(); window.close() }
    let rect = button.convert(button.bounds, to: nil)
    let click = event(in: window, point: NSPoint(x: rect.midX, y: rect.midY))
    XCTAssertTrue(interaction.handle(click) === click)
    XCTAssertEqual(window.fullscreenRequests, 0)
  }

  func testRepeatedClicksDuringTransitionDoNotToggleAgain() {
    let window = window()
    let interaction = DesktopWindowInteraction()
    interaction.attach(to: window)
    defer { interaction.detach(); window.close() }
    XCTAssertNil(interaction.handle(event(in: window)))
    XCTAssertNil(interaction.handle(event(in: window)))
    XCTAssertNil(interaction.handle(event(in: window, clicks: 3)))
    XCTAssertEqual(window.fullscreenRequests, 1)
    NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
    XCTAssertNil(interaction.handle(event(in: window)))
    XCTAssertEqual(window.fullscreenRequests, 2)
  }

  func testOtherWindowsAndDetachedInteractionPassThrough() {
    let window = window()
    let other = self.window()
    let interaction = DesktopWindowInteraction()
    interaction.attach(to: window)
    defer { interaction.detach(); window.close(); other.close() }
    let foreign = event(in: other)
    XCTAssertTrue(interaction.handle(foreign) === foreign)
    interaction.detach()
    let detached = event(in: window)
    XCTAssertTrue(interaction.handle(detached) === detached)
    XCTAssertEqual(window.fullscreenRequests, 0)
    XCTAssertEqual(other.fullscreenRequests, 0)
  }
}
