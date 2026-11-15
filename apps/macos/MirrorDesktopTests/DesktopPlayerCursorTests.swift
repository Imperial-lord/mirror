import XCTest

@testable import MirrorDesktop

@MainActor
final class DesktopPlayerCursorTests: XCTestCase {
  func testIdleHidesAndMouseMovementRestoresBeforeAnotherIdlePeriod() {
    var visibilityChanges: [Bool] = []
    let cursor = DesktopPlayerCursor { visibilityChanges.append($0) }
    cursor.update(controlsVisible: false, pointerInside: true, activeWindow: true)
    XCTAssertTrue(cursor.hidden)
    // Pointer movement reveals chrome and starts a new idle period.
    cursor.restore()
    cursor.update(controlsVisible: false, pointerInside: true, activeWindow: true)
    XCTAssertEqual(visibilityChanges, [true, false, true])
    cursor.restore()
    XCTAssertFalse(cursor.hidden)
  }

  func testPauseLoadingAndSettingsRestoreCursorWithoutMouseMovement() {
    var visibilityChanges: [Bool] = []
    let cursor = DesktopPlayerCursor { visibilityChanges.append($0) }
    for _ in 0..<3 {
      cursor.update(controlsVisible: false, pointerInside: true, activeWindow: true)
      cursor.update(controlsVisible: true, pointerInside: true, activeWindow: true)
    }
    XCTAssertEqual(visibilityChanges, [true, false, true, false, true, false])
  }

  func testLeavingOrDeactivatingWindowNeverLeavesCursorHidden() {
    var visibilityChanges: [Bool] = []
    let cursor = DesktopPlayerCursor { visibilityChanges.append($0) }
    cursor.update(controlsVisible: false, pointerInside: false, activeWindow: true)
    cursor.update(controlsVisible: false, pointerInside: true, activeWindow: false)
    XCTAssertTrue(visibilityChanges.isEmpty)
    cursor.update(controlsVisible: false, pointerInside: true, activeWindow: true)
    cursor.update(controlsVisible: false, pointerInside: true, activeWindow: false)
    cursor.restore()
    cursor.restore()
    XCTAssertEqual(
      visibilityChanges, [true, false], "Do not manipulate global cursor visibility repeatedly")
  }
}
