import AppKit
import SwiftUI

/// Observe the existing titlebar rather than placing a hit-testing layer over the app.
struct DesktopWindowChrome: NSViewRepresentable {
  func makeCoordinator() -> DesktopWindowInteraction { DesktopWindowInteraction() }
  func makeNSView(context: Context) -> NSView { AttachmentView(interaction: context.coordinator) }
  func updateNSView(_ nsView: NSView, context: Context) {}
  static func dismantleNSView(_ nsView: NSView, coordinator: DesktopWindowInteraction) {
    coordinator.detach()
  }

  private final class AttachmentView: NSView {
    let interaction: DesktopWindowInteraction
    init(interaction: DesktopWindowInteraction) {
      self.interaction = interaction
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { interaction.attach(to: window) }
  }
}

@MainActor final class DesktopWindowInteraction {
  private weak var window: NSWindow?
  private var monitor: Any?
  private var observations: [NSObjectProtocol] = []
  private var consumeMouseUp = false
  private var transitioning = false
  private var recovery: Task<Void, Never>?

  func attach(to window: NSWindow?) {
    guard window !== self.window else { return }
    detach()
    self.window = window
    guard let window else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self else { return false }
        return self.handle(event) == nil
      }
      return consumed ? nil : event
    }
    let center = NotificationCenter.default
    for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
      observations.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.beginTransition() }
      })
    }
    for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
      observations.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.finishTransition() }
      })
    }
  }

  func detach() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    for observation in observations { NotificationCenter.default.removeObserver(observation) }
    observations = []
    recovery?.cancel()
    recovery = nil
    window = nil
    transitioning = false
    consumeMouseUp = false
  }

  func handle(_ event: NSEvent) -> NSEvent? {
    guard let window, event.window === window else { return event }
    if event.type == .leftMouseUp, consumeMouseUp {
      consumeMouseUp = false
      return nil
    }
    guard event.type == .leftMouseDown, event.clickCount >= 2,
      window.attachedSheet == nil, window.styleMask.contains(.resizable),
      isTitlebar(event.locationInWindow, in: window) else { return event }
    consumeMouseUp = true
    if event.clickCount == 2, !transitioning {
      beginTransition()
      window.toggleFullScreen(nil)
    }
    // Prevent AppKit's separate titlebar double-click zoom/minimize action.
    return nil
  }

  private func isTitlebar(_ point: NSPoint, in window: NSWindow) -> Bool {
    let height = max(28, window.frame.height - window.contentLayoutRect.height)
    guard point.x >= 0, point.x <= window.frame.width,
      point.y >= window.frame.height - height, point.y <= window.frame.height else { return false }
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      if let button = window.standardWindowButton(type),
        button.convert(button.bounds, to: nil).insetBy(dx: -4, dy: -4).contains(point) { return false }
    }
    if let frame = window.contentView?.superview {
      var hit = frame.hitTest(frame.convert(point, from: nil))
      while let view = hit {
        if view is NSControl { return false }
        hit = view.superview
      }
    }
    return true
  }

  private func beginTransition() {
    transitioning = true
    recovery?.cancel()
    // A refused transition may not send a did-enter/exit notification.
    recovery = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
      self?.finishTransition()
    }
  }
  private func finishTransition() {
    transitioning = false
    recovery?.cancel()
    recovery = nil
  }
}
