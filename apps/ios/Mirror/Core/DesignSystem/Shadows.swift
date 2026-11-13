import SwiftUI

public extension View {
    func shadowCard() -> some View {
        shadow(color: Color.mirrorOnInk.opacity(0.25), radius: 12, x: 0, y: 4)
    }

    func shadowElevated() -> some View {
        shadow(color: Color.mirrorOnInk.opacity(0.40), radius: 20, x: 0, y: 8)
    }

    func shadowGlow() -> some View {
        shadow(color: Color.mirrorAccent.opacity(0.30), radius: 16, x: 0, y: 0)
    }

    func shadowSoft() -> some View {
        shadow(color: Color.mirrorOnInk.opacity(0.15), radius: 8, x: 0, y: 2)
    }
}
