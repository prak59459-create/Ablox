import SwiftUI
import AbloxCore

public enum MenuTab: String, CaseIterable, Identifiable {
    case play = "Play"
    case games = "Games"
    case worlds = "Worlds"
    case avatar = "Avatar"
    case shop = "Shop"
    case settings = "Settings"

    public var id: String { rawValue }

    /// The sidebar label. `rawValue` is the tab's identity and must not follow
    /// the interface language.
    var displayName: String {
        switch self {
        case .play: return L("Play")
        case .games: return L("Games")
        case .worlds: return L("Worlds")
        case .avatar: return L("Avatar")
        case .shop: return L("Shop")
        case .settings: return L("Settings")
        }
    }

    var icon: AbloxIcon {
        switch self {
        case .play: return .gamepad
        case .games: return .compass
        case .worlds: return .stack
        case .avatar: return .person
        case .shop: return .cart
        case .settings: return .gearCog
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
    @EnvironmentObject private var saves: GameSaves
    @EnvironmentObject private var updater: AppUpdater
    @EnvironmentObject private var cloud: CloudService
    @EnvironmentObject private var notices: NoticeService

    @State private var selectedTab: MenuTab = .play
    /// Set when the player enters a world; drives the full-screen cover.
    @State private var activeSession: ActiveSession?
    /// A game on its way in, waiting for a sheet to finish leaving.
    @State private var startingSession = false
    /// The new version being handed to Swift Playgrounds.
    @State private var installing: UpdateInstall?
    /// Why a game could not start (Settings → Family).
    @State private var blockedMessage: String?
    /// Today's coins for coming back, to say so.
    @State private var dailyBonus: Int?

    public init() {}

    // In three parts — the screen, what it presents, what it watches —
    // each type-checked on its own. As one long chain this was one of the
    // slowest things in the app to compile.
    public var body: some View {
        watching(presenting(layout))
    }

    private var layout: some View {
        ZStack {
            DynamicBackgroundView()

            HStack(spacing: 0) {
                SidebarView(selectedTab: $selectedTab)
                    .frame(width: Ablox.Metrics.sidebarWidth)
                    // On the sidebar rather than the screen: one alert per view.
                    .alert(L("Welcome back!"), isPresented: Binding(get: { dailyBonus != nil }, set: { if !$0 { dailyBonus = nil } })) {
                        Button(L("Thanks!"), role: .cancel) { dailyBonus = nil }
                    } message: {
                        Text(verbatim: L("Here are {} coins for coming back. Day {} in a row!", dailyBonus ?? 0, settings.memory.dailyBonus.streak))
                    }

                Divider().background(Ablox.Palette.line)

                VStack(spacing: 0) {
                    UpdateBanner(updater: updater) { beginInstall() }
                    NoticeBanner(service: notices)
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(AnyTransition.opacity)
                }
            }
        }
        .abloxColorScheme()
        .tint(Ablox.Palette.accent)
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .play:
            PlayLobbyView(onEnter: enter)
        case .games:
            DiscoverView(onEnter: enter)
        case .worlds:
            WorldsLobbyView(onEnter: enter)
        case .avatar:
            AvatarCustomizerView()
        case .shop:
            ShopView()
        case .settings:
            SettingsView()
        }
    }

    private func presenting<Content: View>(_ content: Content) -> some View {
        content
            .fullScreenCover(item: $activeSession) { active in
                PlayScreen(session: session, activeSession: active) {
                    session.leave()
                    activeSession = nil
                }
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(saves)
                .environmentObject(cloud)
            }
            .alert(L("Not now"), isPresented: Binding(get: { blockedMessage != nil }, set: { if !$0 { blockedMessage = nil } })) {
                Button(L("OK"), role: .cancel) { blockedMessage = nil }
            } message: {
                Text(verbatim: blockedMessage ?? "")
            }
            .sheet(item: $installing) { install in
                UpdateInstallSheet(updater: updater, backup: install.backup)
            }
            // The first time a new version runs: what changed.
            .sheet(isPresented: Binding(get: { updater.justUpdated != nil && activeSession == nil },
                                        set: { if !$0 { updater.justUpdated = nil } })) {
                if let manifest = updater.justUpdated { WhatsNewSheet(manifest: manifest) }
            }
    }

    private func watching<Content: View>(_ content: Content) -> some View {
        content
            // Settings → Problem reports.
            .onChange(of: store.lastError) { _, error in
                if let error { ProblemRecorder.shared.record(.saving, error) }
            }
            .onChange(of: cloud.state) { _, state in
                if case let .failed(message) = state { ProblemRecorder.shared.record(.cloud, message) }
            }
            .onChange(of: updater.phase) { _, phase in
                if case let .failed(message) = phase { ProblemRecorder.shared.record(.update, message) }
            }
            .task { await notices.refreshIfDue() }
            .onChange(of: activeSession == nil) { _, inMenus in
                if inMenus { ProblemRecorder.shared.noteActivity("In the menus") }
            }
            .onAppear(perform: arrive)
            .onChange(of: settings.cloud) { _, value in
                cloud.configure(value, profile: settings.profile)
            }
            .onChange(of: settings.profile) { _, value in
                cloud.configure(settings.cloud, profile: value)
            }
            .onChange(of: settings.chatFilterEnabled) { _, _ in
                session.moderator = settings.chatModerator
                cloud.moderator = settings.chatModerator
            }
            .onDisappear {
                session.stopBrowsing()
            }
    }

    private func arrive() {
        updater.start()
        let remembered = settings
        session.saveSlotFor = { id in remembered.memory.saveSlots[id.uuidString] ?? 1 }
        // Coins for coming back today.
        if let coins = settings.claimDailyBonus() {
            dailyBonus = coins
        }
        AutoBackup.runIfDue(settings: settings, saves: saves, store: store)
        session.profile = settings.profile
        session.moderator = settings.chatModerator
        session.muteList = settings.muteList
        session.startBrowsing()
        cloud.moderator = settings.chatModerator
        cloud.configure(settings.cloud, profile: settings.profile)
    }
}

extension MainMenuView {
    /// Every way into a world comes through here, so Settings → Family is
    /// checked in one place: time left today, quiet hours, joining others.
    private func enter(_ active: ActiveSession) {
        if let message = PlayGate.message(for: settings.playVerdict) {
            blockedMessage = message
            return
        }
        switch active.mode {
        case .joining where !settings.parental.allowJoiningRooms, .direct where !settings.parental.allowJoiningRooms:
            blockedMessage = L("Joining other people's rooms is turned off in Settings → Family.")
        case let .hosting(world, access) where access != .routerPrivate && !settings.parental.allowPublicRooms:
            start(ActiveSession(mode: .hosting(world, access: .routerPrivate)))
        case let .hosting(world, .internet) where !cloud.allowsInternetPlay:
            start(ActiveSession(mode: .hosting(world, access: .routerPublic)))
        case .cloud where !settings.parental.allowJoiningRooms:
            blockedMessage = L("Joining other people's rooms is turned off in Settings → Family.")
        default:
            start(active)
        }
    }

    /// The game covers the whole screen only when nothing else is up: most
    /// ways in are buttons inside a sheet that is still leaving when they
    /// call this. A second tap while waiting is ignored.
    private func start(_ active: ActiveSession) {
        guard activeSession == nil, !startingSession else { return }
        startingSession = true
        PresentationQueue.whenClear {
            startingSession = false
            activeSession = active
        }
    }

    /// Backs everything up first — a copy stays inside the app too — then
    /// shows how to hand the new version over.
    private func beginInstall() {
        installing = UpdateInstall(backup: saves.makeBackupBeforeUpdate(settings: settings, worlds: store))
    }
}

/// A downloaded update about to be handed over, with the backup made for it.
struct UpdateInstall: Identifiable {
    let id = UUID()
    let backup: URL?
}

/// What the player is about to enter, so `PlayScreen` knows whether it is
/// hosting, joining, or playing alone.
public struct ActiveSession: Identifiable, Equatable {
    public enum Mode: Equatable {
        case solo(WorldDocument)
        case hosting(WorldDocument, access: RoomAccess)
        /// An internet room, through the family's database.
        case cloud(CloudRoom)
        case joining(DiscoveredPeer, code: String)
        /// An invitation (a QR code or text from the host), straight to
        /// the host's address.
        case direct(JoinTicket)
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
        // The drawn cube rather than a stock SF Symbol, so the sidebar shows
        // the actual brand mark — see `AbloxMark`.
        AbloxLockup(subtitle: L("iPad Edition"), markSize: 44)
    }

    private func tabButton(_ tab: MenuTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 15) {
                Image(icon: tab.icon)
                    .font(.title3)
                    .frame(width: 26)
                Text(tab.displayName)
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
                Text(unavailable == nil ? L("TLS 1.3 local mesh") : L("Discovery paused"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(unavailable == nil ? Ablox.Palette.success : Ablox.Palette.warning)
            }

            Text(unavailable ?? L("Searching for nearby iPads over Bonjour."))
                .font(.system(size: 10))
                .foregroundStyle(Ablox.Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
