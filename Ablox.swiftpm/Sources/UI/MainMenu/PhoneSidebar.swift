import SwiftUI
import AbloxCore

/// The main menu's sidebar on an iPhone: the tab icons alone, in a column
/// that scrolls when the phone is on its side, with a dot for whether
/// nearby devices can be found. `SidebarView` is the iPad's.
struct PhoneSidebarView: View {
    @Binding var selectedTab: MenuTab
    let tabs: [MenuTab]
    @EnvironmentObject private var session: SessionCoordinator

    var body: some View {
        VStack(spacing: 8) {
            AbloxMark()
                .frame(width: 30, height: 30)
                .padding(.top, 10)
                .accessibilityHidden(true)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.vertical, 4)
            }

            Circle()
                .fill(session.browserUnavailableReason == nil ? Ablox.Palette.success : Ablox.Palette.warning)
                .frame(width: 8, height: 8)
                .padding(.bottom, 10)
                .accessibilityLabel(session.browserUnavailableReason == nil ? L("TLS 1.3 local mesh") : L("Discovery paused"))
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func tabButton(_ tab: MenuTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(icon: tab.icon)
                    .font(.title3)
                Text(tab.displayName)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 60, height: Ablox.Metrics.minimumTapTarget + 6)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Ablox.Palette.accent.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Ablox.Palette.accent.opacity(0.45), lineWidth: 1)
                        )
                }
            }
            .foregroundStyle(isSelected ? Ablox.Palette.accent : Ablox.Palette.inkMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
