import SwiftUI

public struct SubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            header
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)

            ScrollView {
                VStack(spacing: Spacing.md) {
                    planCard
                    billingOptions

                    Button {} label: {
                        HStack(spacing: Spacing.xs) {
                            PhosphorView(.prohibit, size: 14, color: .mirrorTextSecondary)
                                .accessibilityHidden(true)
                            Text("Unsubscribe")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.mirrorTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, FloatingTabBarView.barHeight)
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

            Text("Subscription")
                .font(.headline)
                .foregroundStyle(Color.mirrorInk)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("Monthly")
                    .font(.subheadline)
                    .foregroundStyle(Color.mirrorTextSecondary)

                Spacer(minLength: Spacing.xs)

                Text("Preview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.mirrorInk)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(Color.mirrorSurfaceFaint, in: Capsule())
            }

            Text("$27.00")
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.mirrorInk)

            Text("Subscription billing isn’t available yet.")
                .font(.footnote)
                .foregroundStyle(Color.mirrorTextSecondary)
                .padding(.top, Spacing.xxs)
        }
        .padding(Spacing.md)
        .background(Color(mirrorHex: "121215"), in: RoundedRectangle(cornerRadius: 16))
    }

    private var billingOptions: some View {
        VStack(spacing: 0) {
            billingRow("Change plan")
            Divider().padding(.horizontal, Spacing.md)
            billingRow("Payment method", detail: "•••• 5647")
            Divider().padding(.horizontal, Spacing.md)
            billingRow("Billing history")
        }
        .background(Color(mirrorHex: "121215"), in: RoundedRectangle(cornerRadius: 16))
    }

    private func billingRow(_ title: LocalizedStringKey, detail: String? = nil) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .fixedSize()
            }
        }
        .foregroundStyle(Color.mirrorTextSecondary)
        .padding(Spacing.md)
        .accessibilityElement(children: .combine)
    }
}
