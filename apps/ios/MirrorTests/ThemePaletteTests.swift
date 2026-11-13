import XCTest
import SwiftUI
import UIKit
@testable import Mirror

final class ThemePaletteTests: XCTestCase {
    func testDarkPreservesOriginalBackgroundSurfacesAndText() {
        XCTAssertEqual(rgba(.mirrorBackground, .dark), [6, 6, 6, 255])
        XCTAssertEqual(rgba(.mirrorSurface1, .dark), [18, 18, 20, 255])
        XCTAssertEqual(rgba(.mirrorSurface2, .dark), [24, 24, 27, 255])
        XCTAssertEqual(rgba(.mirrorSurface3, .dark), [34, 34, 38, 255])
        XCTAssertEqual(rgba(.mirrorInk, .dark), [255, 255, 255, 255])
        XCTAssertEqual(rgba(.mirrorOnInk, .dark), [0, 0, 0, 255])
        XCTAssertEqual(rgba(.mirrorTextTertiary, .dark), [255, 255, 255, 112])
    }
    func testLightUsesLightSurfacesWithoutChangingLiteralAvatarColors() {
        XCTAssertEqual(rgba(.mirrorBackground, .light), [255, 255, 255, 255])
        XCTAssertEqual(rgba(.mirrorSurface1, .light), [242, 242, 244, 255])
        XCTAssertEqual(rgba(.mirrorInk, .light), [0, 0, 0, 255])
        XCTAssertEqual(rgba(.mirrorOnInk, .light), [255, 255, 255, 255])
        XCTAssertEqual(rgba(Color(hex: "222226"), .light), [34, 34, 38, 255])
    }
    private func rgba(_ color: Color, _ style: UIUserInterfaceStyle) -> [Int] {
        let traits = UITraitCollection(userInterfaceStyle: style)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        traits.performAsCurrent {
            XCTAssertTrue(UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a))
        }
        return [r, g, b, a].map { Int(($0 * 255).rounded()) }
    }
}
