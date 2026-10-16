import SwiftUI
import AbloxCore

// The shell of the menus (Ablox NEXT): a bar along the top with your level
// and coins — each opens a small panel — and Settings; a dock of four tabs
// along the bottom; and the two tabs that gather screens which were tabs of
// their own: Play (the games and the rooms) and Me (the closet, the shop and
// your profile).

// MARK: - The bar along the top

struct MenuTopBar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.screenFit) private var fit
    @Binding var tab: MenuTab
    /// Opens a part of Me: the shop from the coins, the badges from the level.
    var onMe: (MeSection) -> Void

    @State private var showingCoins = false
    @State private var showingLevel = false

    private var stats: ProgressStats {
        settings.progressStats(worldsMade: store.entries.count, pictures: 0)
    }

    /// The shop, from the coins — unless a grown-up has put it away.
    private var shopAction: (() -> Void)? {
        guard settings.parental.family.shopAllowed else { return nil }
        return {
            showingCoins = false
            onMe(.shop)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { tab = .home } label: {
                AbloxLockup(subtitle: fit.isCompact ? "" : L("iPad Edition"), markSize: fit.isCompact ? 30 : 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L("Home")))
            Spacer(minLength: 6)
            Button { showingLevel = true } label: { CountPill(.level, "\(stats.level.number)") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L("Level {}", stats.level.number)))
                .popover(isPresented: $showingLevel) {
                    LevelQuickPanel(stats: stats) {
                        showingLevel = false
                        onMe(.profile)
                    }
                    .presentationCompactAdaptation(.sheet)
                }
            Button { showingCoins = true } label: {
                CountPill(.coin, "\(settings.wallet.coins)", colour: Ablox.Palette.warning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L("{} coins", settings.wallet.coins)))
            .popover(isPresented: $showingCoins) {
                CoinsQuickPanel(onShop: shopAction)
                    .presentationCompactAdaptation(.sheet)
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = .settings }
            } label: {
                DrawnIconImage(.settings, size: 30)
                    .padding(5)
                    .background(Circle().fill(tab == .settings ? Ablox.Palette.accent.opacity(0.3) : Ablox.Palette.wash))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L("Settings")))
        }
        .padding(.horizontal, fit.gutter)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().background(Ablox.Palette.line) }
    }
}

/// Your level, the badges nearest, and the way to all of them.
struct LevelQuickPanel: View {
    let stats: ProgressStats
    var onBadges: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LevelCard(level: stats.level)
            Text(L("Nearly there")).font(.headline)
            ForEach(Achievement.nextUp(stats)) { badge in
                BadgeProgressRow(badge: badge, stats: stats)
            }
            Button(action: onBadges) {
                Label { Text(L("Badges")) } icon: { DrawnIconImage(.meTrophies, size: 24) }
            }
            .buttonStyle(BlockButtonStyle(.gold, fullWidth: true))
        }
        .padding(18)
        .frame(minWidth: 320, idealWidth: 360)
        .abloxColorScheme()
    }
}

/// Your coins, what came and went lately, and the shop.
struct CoinsQuickPanel: View {
    @EnvironmentObject private var settings: AppSettings
    var onShop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DrawnIconImage(.coin, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(settings.wallet.coins)")
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                    Text(L("Coins")).font(.caption.weight(.bold)).foregroundStyle(Ablox.Palette.inkMuted)
                }
            }
            let recent = Array(settings.coinLedger.entries.prefix(6))
            if recent.isEmpty {
                Text(L("Earn coins by collecting and finishing rounds, then unlock new colours, faces, hats and pets."))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            } else {
                VStack(spacing: 6) {
                    ForEach(recent) { entry in
                        HStack {
                            Text(verbatim: entry.reason).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(verbatim: entry.amount > 0 ? "+\(entry.amount)" : "\(entry.amount)")
                                .font(.subheadline.weight(.heavy).monospacedDigit())
                                .foregroundStyle(entry.amount > 0 ? Ablox.Palette.success : Ablox.Palette.danger)
                        }
                    }
                }
            }
            if let onShop {
                Button(action: onShop) {
                    Label { Text(L("Shop")) } icon: { DrawnIconImage(.meShirt, size: 24) }
                }
                .buttonStyle(BlockButtonStyle(.green, fullWidth: true))
            }
        }
        .padding(18)
        .frame(minWidth: 300, idealWidth: 340)
        .abloxColorScheme()
    }
}

// MARK: - The dock

/// Four tabs along the bottom: Home, Play, Me, Create. Home shows how many
/// rewards are waiting.
struct MenuDock: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.screenFit) private var fit
    @Binding var tab: MenuTab

    /// Tabs a grown-up has put away do not show.
    private var tabs: [MenuTab] {
        MenuTab.dockTabs.filter { $0 != .create || settings.parental.family.buildingAllowed }
    }

    private var waiting: Int {
        let missions = settings.memory.missions
        let today = PlaytimeLog.dayKey(Date())
        let bonus = settings.memory.dailyBonus.isWaiting() ? 1 : 0
        return bonus + missions.waitingRewards(on: today)
    }

    var body: some View {
        HStack(spacing: fit.isCompact ? 0 : 6) {
            ForEach(tabs) { item in
                button(item)
            }
        }
        .padding(fit.isCompact ? 5 : 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Ablox.Palette.lineStrong, lineWidth: 1.5))
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.35)).offset(y: 5))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .padding(.horizontal, fit.isCompact ? 8 : 0)
        .padding(.bottom, fit.isCompact ? 4 : 10)
    }

    private func button(_ item: MenuTab) -> some View {
        let on = tab == item
        return Button {
            MenuSounds.page()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { tab = item }
        } label: {
            VStack(spacing: 2) {
                DrawnIconImage(item.drawnIcon, size: fit.isCompact ? 34 : 42)
                    .scaleEffect(on ? 1.08 : 1)
                    .offset(y: on ? -2 : 0)
                Text(item.displayName)
                    .font(.system(size: fit.isCompact ? 11 : 13, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? Color.white : Ablox.Palette.inkMuted)
            .frame(width: fit.isCompact ? nil : CGFloat(92), height: fit.isCompact ? 60 : 70)
            .frame(maxWidth: fit.isCompact ? CGFloat.infinity : nil)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.56, blue: 0.97), Color(red: 0.23, green: 0.51, blue: 0.96)],
                                             startPoint: .top, endPoint: .bottom))
                        .background(RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .fill(Color(red: 0.11, green: 0.31, blue: 0.72)).offset(y: 4))
                }
            }
            .overlay(alignment: .topTrailing) {
                if item == .home, waiting > 0 {
                    Text(verbatim: "\(waiting)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Ablox.Palette.danger))
                        .offset(x: -10, y: 2)
                        .accessibilityLabel(Text(L("{} waiting", waiting)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Play: the games and the rooms

struct PlayTabView: View {
    @Environment(\.screenFit) private var fit
    var onEnter: (ActiveSession) -> Void
    @Binding var section: PlaySection
    /// A game whose page should open (a door in the Plaza).
    var opening: Binding<String?>?

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Play"), selection: $section) {
                ForEach(PlaySection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal, fit.gutter)
            .padding(.top, 12)
            switch section {
            case .games: DiscoverView(onEnter: onEnter, opening: opening)
            case .rooms: PlayLobbyView(onEnter: onEnter)
            }
        }
    }
}

enum PlaySection: String, CaseIterable, Identifiable {
    case games, rooms
    var id: String { rawValue }
    var title: String {
        switch self {
        case .games: return L("Games")
        case .rooms: return L("Rooms")
        }
    }
}

// MARK: - Me: the closet, the shop, your profile

enum MeSection: String, CaseIterable, Identifiable {
    case closet, shop, profile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .closet: return L("Closet")
        case .shop: return L("Shop")
        case .profile: return L("Profile")
        }
    }
}

struct MeTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.screenFit) private var fit
    @Binding var section: MeSection

    private var sections: [MeSection] {
        MeSection.allCases.filter { $0 != .shop || settings.parental.family.shopAllowed }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Me"), selection: $section) {
                ForEach(sections) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)
            .padding(.horizontal, fit.gutter)
            .padding(.top, 12)
            .padding(.bottom, 6)
            switch section {
            case .closet: AvatarCustomizerView()
            case .shop: ShopView()
            case .profile: ProfileSheet(embedded: true)
            }
        }
        .onChange(of: settings.parental) { _, parental in
            if section == .shop && !parental.family.shopAllowed { section = .closet }
        }
    }
}
