import SwiftUI

public struct ScaleButtonStyle: ButtonStyle {
    public var scaleAmount: CGFloat

    public init(scaleAmount: CGFloat = 0.96) {
        self.scaleAmount = scaleAmount
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
