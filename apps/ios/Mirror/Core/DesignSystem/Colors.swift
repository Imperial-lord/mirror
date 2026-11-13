import SwiftUI
import UIKit

public extension Color {
    static let mirrorInk = Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .black })
    static let mirrorOnInk = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
    // Exact Behance Design System Tokens from Sasha Dobrynina's Mirror:
    // [06] Primary Background: #060606
    static let mirrorBackground = Color(mirrorHex: "060606")
    static let mirrorBlack      = Color(mirrorHex: "060606")

    // Elevated surfaces
    static let mirrorCard       = Color(mirrorHex: "121214")
    static let mirrorSurface1   = Color(mirrorHex: "121214")
    static let mirrorSurface2   = Color(mirrorHex: "18181B")
    static let mirrorSurface3   = Color(mirrorHex: "222226")

    // [01] Primary: #FFFFFF (100%)
    static let mirrorTextPrimary   = Color(mirrorHex: "FFFFFF")
    static let mirrorWhite         = Color(mirrorHex: "FFFFFF")

    // [02] Secondary Active: #FFFFFF @ 64% opacity
    static let mirrorTextSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.64) : UIColor.black.withAlphaComponent(0.70) })

    // [03] Tertiary: #FFFFFF @ 44% opacity
    static let mirrorTextTertiary  = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.44) : UIColor.black.withAlphaComponent(0.58) })

    // [04] Inactive / Divider: #FFFFFF @ 20% opacity
    static let mirrorBorder        = Color.mirrorInk.opacity(0.20)

    // [05] Quaternary: #FFFFFF @ 9% opacity
    static let mirrorSurfaceFaint  = Color.mirrorInk.opacity(0.09)

    // Accents in Behance design:
    // Primary CTA is crisp White #FFFFFF with Black text.
    static let mirrorAccent        = Color(mirrorHex: "FFFFFF")
    static let mirrorAccentDark    = Color(mirrorHex: "E5E5E5")

    // Semantic
    static let mirrorRed           = Color(mirrorHex: "FF3B30")
    static let mirrorAmber         = Color(mirrorHex: "FFCC00")

    init(hex: String) { self.init(hex: hex, adapts: false) }

    /// A design-system color that keeps the supplied hex exactly in Dark mode.
    init(mirrorHex: String) { self.init(hex: mirrorHex, adapts: true) }

    private init(hex: String, adapts: Bool) {
        let cleanHex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        let dark = UIColor(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, alpha: 1)
        let lightHex: UInt64?
        switch cleanHex.uppercased() {
        case "060606", "000000": lightHex = 0xFFFFFF
        case "121214", "121215", "111111", "141417", "151518": lightHex = 0xF2F2F4
        case "18181B", "1C1C1C", "1A1A1A", "171719": lightHex = 0xE9E9ED
        case "222226", "222222", "2C2C2E": lightHex = 0xDEDEE4
        case "FFFFFF": lightHex = 0x111111
        case "E5E5E5": lightHex = 0x333333
        case "EF4444", "FF3B30": lightHex = 0xB42318
        default: lightHex = nil
        }
        if adapts, let hex = lightHex {
            let light = UIColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
            self.init(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        } else { self.init(dark) }
    }
}
