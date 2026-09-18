import SwiftUI

public enum MenuTab: String, CaseIterable, Identifiable {
    case play = "Play"
    case worlds = "Worlds"
    case avatar = "Avatar"
    case settings = "Settings"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .play: return "gamecontroller.fill"
        case .worlds: return "square.stack.3d.up.fill"
        case .avatar: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// The app's hub. Sidebar on the left, tab content on the right.
///
/// Fixed two-pane rather than `NavigationSplitView` because the sidebar is
/// always visible on iPad in landscape and never collapses — the lobby is the
/// point of the screen, and a collapsible sidebar would hide the connection
/// status that tells you whether anything is findable.
public struct MainMenuView: View {
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    @State private var selectedTab: MenuTab = .play
    /// Set when the player enters a world; drives the full-screen cover.
    @State private var activeSession: ActiveSession?

    public init() {}

    public var body: some View {
        ZStack {
            DynamicBackgroundView()

            HStack(spacing: 0) {
                SidebarView(selectedTab: $selectedTab)
                    .frame(width: Ablox.Metrics.sidebarWidth)

                Divider().background(Color.white.opacity(0.08))

                Group {
                    switch selectedTab {
                    case .play:
                        PlayLobbyView(onEnter: { activeSession = $0 })
                    case .worlds:
                        WorldsLobbyView(onEnter: { activeSession = $0 })
                    case .avatar:
                        AvatarCustomizerView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Ablox.Palette.accent)
        .fullScreenCover(item: $activeSession) { active in
            PlayScreen(session: session, activeSession: active) {
                session.leave()
                activeSession = nil
            }
        }
        .onAppear {
            session.profile = settings.profile
            session.startBrowsing()
        }
        .onDisappear {
            session.stopBrowsing()
        }
    }
}

/// What the player is about to enter, so `PlayScreen` knows whether it is
/// hosting, joining, or playing alone.
public struct ActiveSession: Identifiable, Equatable {
    public enum Mode: Equatable {
        case solo(WorldDocument)
        case hosting(WorldDocument)
        case joining(DiscoveredPeer, code: String)
    }

    public let id = UUID()
    public let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }

    public static func == (lhs: ActiveSession, rhs: ActiveSession) -> Bool { lhs.id == rhs.id }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTab: MenuTab
    @EnvironmentObject private var session: SessionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandmark
                .padding(.horizontal, 20)
                .padding(.top, 28)

            VStack(spacing: 6) {
                ForEach(MenuTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            connectionStatus
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .background(.ultraThinMaterial)
    }

    private var brandmark: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Ablox.Palette.brand)
                    .frame(width: 44, height: 44)
                Image(systemName: "cube.fill")
                    .font(.title2)
                    .foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("ABLOX")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, Ablox.Palette.accent], startPoint: .leading, endPoint: .trailing)
                    )
                Text("iPad Edition")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ablox for iPad")
    }

    private func tabButton(_ tab: MenuTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 15) {
                Image(systemName: tab.icon)
                    .font(.title3)
                    .frame(width: 26)
                Text(tab.rawValue)
                    .font(.body.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Ablox.Palette.accent.opacity(0.26), Ablox.Palette.accentDeep.opacity(0.18)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Ablox.Palette.accent.opacity(0.45), lineWidth: 1)
                        )
                }
            }
            .foregroundStyle(isSelected ? Ablox.Palette.accent : Ablox.Palette.inkMuted)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var connectionStatus: some View {
        let unavailable = session.browserUnavailableReason

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(unavailable == nil ? Ablox.Palette.success : Ablox.Palette.warning)
                    .frame(width: 8, height: 8)
                Text(unavailable == nil ? "TLS 1.3 local mesh" : "Discovery paused")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(unavailable == nil ? Ablox.Palette.success : Ablox.Palette.warning)
            }

            Text(unavailable ?? "Searching for nearby iPads over Bonjour.")
                .font(.system(size: 10))
                .foregroundStyle(Ablox.Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
