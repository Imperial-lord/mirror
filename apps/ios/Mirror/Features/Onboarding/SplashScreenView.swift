import SwiftUI

public struct SplashScreenView: View {
    public var onFinished: () -> Void

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Color("LaunchBackground")
            Image("LaunchMark")
                .accessibilityLabel("Mirror")
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    onFinished()
                }
            }
        }
    }
}
