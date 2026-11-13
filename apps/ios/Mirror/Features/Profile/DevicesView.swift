import SwiftUI
import UIKit

public struct DevicesView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            header
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        currentDevice

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            sectionHeading("Other devices")
                            Text("Other devices aren’t tracked yet.")
                                .font(.subheadline)
                                .foregroundStyle(Color.mirrorTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Spacing.md)
                                .background(Color(mirrorHex: "121215"), in: RoundedRectangle(cornerRadius: 14))
                        }

                        Spacer(minLength: 0)

                        smartTVFooter
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.bottom, FloatingTabBarView.barHeight + Spacing.md)
        .background(Color.mirrorBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                dismiss()
            } label: {
                PhosphorView(.caretLeft, size: 16, color: .mirrorInk)
                    .frame(width: 44, height: 44)
                    .background(Color(mirrorHex: "121215"), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("My Devices")
                .font(.headline)
                .foregroundStyle(Color.mirrorInk)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var currentDevice: some View {
        let device = UIDevice.current
        let icon: PhosphorIcon = device.userInterfaceIdiom == .pad ? .tablet : .phone
        let system = "\(device.systemName) \(device.systemVersion)"
        #if targetEnvironment(simulator)
        let model = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? device.model
        let detail = "\(system) • Simulator"
        #else
        let model = device.model
        let detail = system
        #endif

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeading("Current device")

            HStack(spacing: 14) {
                PhosphorView(icon, size: 22, color: .mirrorInk)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.mirrorInk)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.mirrorTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color(mirrorHex: "121215"), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        }
    }

    private var smartTVFooter: some View {
        VStack(spacing: Spacing.xs) {
            Text("Smart TV pairing isn’t available yet.")
                .font(.footnote)
                .foregroundStyle(Color.mirrorTextSecondary)
                .multilineTextAlignment(.center)

            Button("Connect Smart TV") {}
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.mirrorTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(mirrorHex: "121215"), in: Capsule())
                .buttonStyle(.plain)
                .disabled(true)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.mirrorTextSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
