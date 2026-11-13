import SwiftUI

public struct OnboardingView: View {
    public var onComplete: () -> Void

    @State private var currentIndex = 0

    private struct SlideData {
        let title: String
        let subtitle: String
        let icon: PhosphorIcon
    }

    private let slides = [
        SlideData(
            title: "Watch latest movies in one click",
            subtitle: "Mirror is the largest movie streaming platform of internet.",
            icon: .playCircleLinear
        ),
        SlideData(
            title: "Download to your phone to watch offline",
            subtitle: "Download movies and TV shows to your device and watch them even without an internet connection.",
            icon: .downloadLinear
        ),
        SlideData(
            title: "Personalized recommendations",
            subtitle: "Discover high quality cinema matched specifically to your tastes and watching history.",
            icon: .magicStar
        )
    ]

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Skip Bar (Behance Board 09)
                HStack {
                    Spacer()
                    Button(action: {
                        HapticManager.shared.selection()
                        onComplete()
                    }) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.mirrorTextTertiary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                    }
                }
                .padding(.top, Spacing.xs)

                Spacer()

                // Slide Content
                TabView(selection: $currentIndex) {
                    ForEach(0..<slides.count, id: \.self) { index in
                        VStack(spacing: 28) {
                            // Hero Icon Artwork
                            ZStack {
                                Circle()
                                    .fill(Color(mirrorHex: "121215"))
                                    .frame(width: 160, height: 160)
                                    .overlay(
                                        Circle().stroke(Color.mirrorInk.opacity(0.08), lineWidth: 1)
                                    )

                                PhosphorView(slides[index].icon, size: 72, color: Color.mirrorInk)
                            }

                            VStack(spacing: 12) {
                                Text(slides[index].title)
                                    .font(.system(size: 26, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(Color.mirrorInk)
                                    .padding(.horizontal, Spacing.lg)

                                Text(slides[index].subtitle)
                                    .font(.system(size: 15))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(Color.mirrorInk.opacity(0.55))
                                    .lineSpacing(4)
                                    .padding(.horizontal, Spacing.xl)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 380)

                // Custom Pagination Dots (Behance Board 09)
                HStack(spacing: 8) {
                    ForEach(0..<slides.count, id: \.self) { index in
                        if currentIndex == index {
                            Capsule()
                                .fill(Color.mirrorInk)
                                .frame(width: 20, height: 6)
                        } else {
                            Circle()
                                .fill(Color.mirrorInk.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: currentIndex)
                .padding(.top, Spacing.lg)

                Spacer()

                // Solid White Capsule CTA Button (Behance Board 09)
                Button(action: {
                    HapticManager.shared.impact(.medium)
                    if currentIndex < slides.count - 1 {
                        withAnimation {
                            currentIndex += 1
                        }
                    } else {
                        onComplete()
                    }
                }) {
                    Text(currentIndex == slides.count - 1 ? "Get Started" : "Next")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.mirrorOnInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.mirrorInk)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
        }
    }
}
