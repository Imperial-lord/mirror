import SwiftUI

public enum AppTab: Int, CaseIterable, Identifiable {
    case home = 0
    case catalog = 1
    case library = 2
    case account = 3

    public var id: Int { rawValue }
}

public struct FloatingTabBarView: View {
    static let barHeight: CGFloat = 54
    @Binding public var selectedTab: AppTab

    public init(selectedTab: Binding<AppTab>) {
        self._selectedTab = selectedTab
    }

    public var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .home, activeIcon: .homeBold, inactiveIcon: .homeLinear)
            Spacer()
            tabButton(tab: .catalog, activeIcon: .searchLinear, inactiveIcon: .searchLinear)
            Spacer()
            tabButton(tab: .library, activeIcon: .bookmarkLinear, inactiveIcon: .bookmarkLinear)
            Spacer()
            accountTabButton
        }
        .padding(.horizontal, 24)
        .frame(height: Self.barHeight)
        .background {
            Color(mirrorHex: "060606").opacity(0.96)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.mirrorInk.opacity(0.06)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }

    }

    private func tabButton(tab: AppTab, activeIcon: PhosphorIcon, inactiveIcon: PhosphorIcon) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            selectedTab = tab
        }) {
            let isSelected = selectedTab == tab
            PhosphorView(
                isSelected ? activeIcon : inactiveIcon,
                size: 22,
                color: isSelected ? Color.mirrorInk : Color.mirrorInk.opacity(0.40)
            )
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(tab == .catalog ? "Catalog" : tab == .library ? "Library" : "Home")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .buttonStyle(ScaleButtonStyle(scaleAmount: 0.90))
    }

    private var accountTabButton: some View {
        Button(action: {
            HapticManager.shared.selection()
            selectedTab = .account
        }) {
            Group {
                if let profile = AuthService.shared.currentProfile {
                    ProfileAvatarView(profile: profile, size: 28)
                } else {
                    PhosphorView(.profileLinear, size: 28).foregroundStyle(Color.mirrorInk)
                }
            }
            .overlay(
                Circle()
                    .stroke(selectedTab == .account ? Color.mirrorInk : Color.clear, lineWidth: 1.2)
            )
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Account")
        .accessibilityAddTraits(selectedTab == .account ? .isSelected : [])
        .buttonStyle(ScaleButtonStyle(scaleAmount: 0.90))
    }
}
