import SwiftUI
import UIKit
import AbloxCore

public enum MenuTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case play = "Play"
    case me = "Me"
    case create = "Create"
    case settings = "Settings"

    public var id: String { rawValue }

    /// The tab's name. `rawValue` is the tab's identity and must not follow
    /// the interface language.
    var displayName: String {
        switch self {
        case .home: return L("Home")
        case .play: return L("Play")
        case .me: return L("Me")
        case .create: return L("Create")
        case .settings: return L("Settings")
        }
    }

    var icon: AbloxIcon {
        switch self {
        case .home: return .homeFilled
        case .play: return .gamepad
        case .me: return .person
        case .create: return .hammer
        case .settings: return .gearCog
        }
    }

    /// The drawn icon on the dock.
    var drawnIcon: DrawnIcon {
        switch self {
        case .home: return .home
        case .play: return .play
        case .me: return .me
        case .create: return .create
        case .settings: return .settings
        }
    }

    /// Along the bottom; Settings is the gear at the top.
    static let dockTabs: [MenuTab] = [.home, .play, .me, .create]

    /// A tab by its name, including the names from before the dock (a saved
    /// "Open Ablox on", the launch check): the tab that has that screen now.
    static func named(_ raw: String) -> MenuTab? {
        switch raw {
        case "Games", "Rooms": return .play
        case "Worlds": return .create
        case "Avatar", "Shop": return .me
        default: return MenuTab(rawValue: raw)
        }
    }
}

/// The app's hub (Ablox NEXT): a bar along the top with your level, coins
/// and Settings, the tab in the middle, and a dock of four tabs along the
/// bottom — Home, Play, Me, Create — the same as the browser version.
public struct MainMenuView: View {
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var saves: GameSaves
    @EnvironmentObject private var updater: AppUpdater
    @EnvironmentObject private var cloud: CloudService
    @EnvironmentObject private var notices: NoticeService
    @Environment(\.screenFit) private var fit

    @State private var selectedTab: MenuTab = .home
    @State private var meSection: MeSection = .closet
    @State private var playSection: PlaySection = .games
    @State private var openedStartTab = false
    /// Set when the player enters a world; drives the full-screen cover.
    @State private var activeSession: ActiveSession?
    /// A game on its way in, waiting for a sheet to finish leaving.
    @State private var startingSession = false
    /// For the card after a game: what things were like going in, and how
    /// the game was entered (for Play again).
    @State private var summaryStart: SessionSummary.Snapshot?
    @State private var lastMode: ActiveSession.Mode?
    @State private var summary: SummaryCard?
    @State private var lastGameName = ""
    /// A friend who has started playing nearby.
    @State private var sightings = FriendSightings()
    @State private var friendNearby: FriendNearby?
    @StateObject private var connectivity = ConnectivityMonitor()
    /// The new version being handed to Swift Playgrounds.
    @State private var installing: UpdateInstall?
    /// Why a game could not start (Settings → Family).
    @State private var blockedMessage: String?
    /// Today's coins for coming back, to say so.
    @State private var dailyBonus: Int?
    /// The Plaza, and the door walked into there.
    @StateObject private var plaza = PlazaTrip()
    /// A game whose page the Games tab should open.
    @State private var openingGame: String?

    public init() {}

    // In three parts — the screen, what it presents, what it watches —
    // each type-checked on its own. As one long chain this was one of the
    // slowest things in the app to compile.
    public var body: some View {
        watching(presenting(layout))
            .abloxAccess(settings.preferences.access)
            .onChange(of: selectedTab) { _, tab in
                // Access: each tab's name read aloud.
                if settings.preferences.access.readTabsAloud { LineReader.shared.speak(tab.displayName) }
            }
            .onChange(of: settings.parental) { _, parental in
                // A tab put away while open: back Home.
                if selectedTab == .create && !parental.family.buildingAllowed { selectedTab = .home }
            }
    }

    private var layout: some View {
        ZStack {
            DynamicBackgroundView()

            VStack(spacing: 0) {
                MenuTopBar(tab: $selectedTab, onMe: openMe)
                    // On the bar rather than the screen: one alert per view.
                    .alert(L("Welcome back!"), isPresented: Binding(get: { dailyBonus != nil }, set: { if !$0 { dailyBonus = nil } })) {
                        Button(L("Thanks!"), role: .cancel) { dailyBonus = nil }
                    } message: {
                        Text(verbatim: bonusMessage)
                    }
                UpdateBanner(updater: updater) { beginInstall() }
                OfflineBanner(monitor: connectivity)
                NoticeBanner(service: notices)
                if let friendNearby {
                    FriendNearbyBanner(name: friendNearby.name, world: friendNearby.peer.worldName,
                                       onJoin: { joinFriend(friendNearby.peer) },
                                       onClose: { withAnimation { self.friendNearby = nil } })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(AnyTransition.opacity)
                    // Scrolled content goes under the dock, and stops above it at the end.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        MenuDock(tab: $selectedTab)
                    }
            }
        }
        .abloxColorScheme()
        .tint(Ablox.Palette.accent)
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeView(onEnter: enter, onOpen: { tab in withAnimation { selectedTab = tab } }, onPlaza: openPlaza)
        case .play:
            PlayTabView(onEnter: enter, section: $playSection, opening: $openingGame)
        case .me:
            MeTabView(section: $meSection)
        case .create:
            WorldsLobbyView(onEnter: enter)
        case .settings:
            SettingsView()
        }
    }

    /// A part of Me, from the bar at the top.
    private func openMe(_ section: MeSection) {
        meSection = section
        withAnimation { selectedTab = .me }
    }

    private func leaveSession() {
        lastGameName = session.world.name
        session.localTouch = nil
        session.leave()
        activeSession = nil
    }

    /// The Plaza: a world to walk around, with a door to each of a few games.
    private func openPlaza() {
        Task {
            guard let world = await plaza.build(settings: settings) else { return }
            let trip = plaza
            session.localTouch = { blockID in
                guard trip.isDoor(blockID) else { return false }
                // Not in the middle of the frame that noticed the touch.
                if trip.walkThrough(blockID) { Task { @MainActor in leaveSession() } }
                return true
            }
            enter(ActiveSession(mode: .solo(world)))
            // Only a walk: no card afterwards.
            summaryStart = nil
        }
    }

    /// Once the play screen has gone: the card about the game, or the page
    /// behind the Plaza door walked into.
    private func afterSession() {
        showSummary()
        guard let door = plaza.takeDoor() else { return }
        switch door {
        case let .game(id):
            playSection = .games
            openingGame = id
            withAnimation { selectedTab = .play }
        case .closet:
            openMe(.closet)
        case .allGames:
            playSection = .games
            withAnimation { selectedTab = .play }
        }
    }

    private func presenting<Content: View>(_ content: Content) -> some View {
        content
            .fullScreenCover(item: $activeSession, onDismiss: afterSession) { active in
                PlayScreen(session: session, activeSession: active, onExit: leaveSession)
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
            .sheet(item: $summary) { card in
                SessionSummarySheet(summary: card.summary, levelUp: card.levelUp, badgeCoins: card.badgeCoins, onPlayAgain: playAgain(card))
            }
            // The first time a new version runs: what changed.
            .sheet(isPresented: Binding(get: { updater.justUpdated != nil && activeSession == nil && summary == nil },
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
            // Update problems are written by the updater itself, with their codes.
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
            // The family's filter choices: strict, and words of their own.
            .onChange(of: settings.parental) { _, _ in
                session.moderator = settings.chatModerator
                cloud.moderator = settings.chatModerator
            }
            .onDisappear {
                session.stopBrowsing()
            }
            .onChange(of: session.discoveredPeers) { _, peers in noticeFriends(in: peers) }
    }

    private func arrive() {
        // Access: the tab chosen to open first, once per launch.
        if !openedStartTab {
            openedStartTab = true
            if let tab = MenuTab.named(settings.preferences.access.startTab ?? "") { selectedTab = tab }
            // The launch check on a simulator opens each tab in turn with a
            // launch argument (scripts/ios-launch-check.sh). An iPad never
            // passes one. "Shop" and "Rooms" open those parts of Me and Play.
            let opened = UserDefaults.standard.string(forKey: "AbloxOpenTab") ?? ""
            if let tab = MenuTab.named(opened) { selectedTab = tab }
            if opened == "Shop" { meSection = .shop }
            if opened == "Rooms" { playSection = .rooms }
            // …and on an iPhone, held upright and on its side
            // (-AbloxOrientation landscape / portrait). Never passed on a
            // real device, so nothing changes there.
            if let turn = UserDefaults.standard.string(forKey: "AbloxOrientation") {
                let mask: UIInterfaceOrientationMask = turn == "landscape" ? .landscapeRight : .portrait
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                        print("AbloxOrientation: \(error.localizedDescription)")
                    }
                }
            }
            // Its frame-rate run goes straight into a busy world and prints
            // how fast it draws (`RenderBenchmark`).
            if UserDefaults.standard.bool(forKey: "AbloxPlayBenchmark") {
                enter(ActiveSession(mode: .solo(RenderBenchmark.world())))
            }
        }
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

    /// The welcome-back message, with the weekend and any streak prize said.
    var bonusMessage: String {
        let streak = settings.memory.dailyBonus.streak
        var text = L("Here are {} coins for coming back. Day {} in a row!", dailyBonus ?? 0, streak)
        if StreakRewards.weekendMultiplier(on: Date()) > 1 { text += "\n" + L("It's the weekend: twice the coins!") }
        if let prize = StreakRewards.bonus(forStreak: streak) { text += "\n" + L("That includes a {}-day prize of {} coins!", streak, prize) }
        return text
    }

    /// Every way into a world comes through here, so Settings → Family is
    /// checked in one place: time left today, quiet hours, joining others.
    private func enter(_ active: ActiveSession) {
        if let message = PlayGate.message(for: settings.playVerdict) {
            refuse(message)
            return
        }
        switch active.mode {
        case .joining where !settings.parental.allowJoiningRooms, .direct where !settings.parental.allowJoiningRooms:
            refuse(L("Joining other people's rooms is turned off in Settings → Family."))
        case let .hosting(world, access) where access != .routerPrivate && !settings.parental.allowPublicRooms:
            start(ActiveSession(mode: .hosting(world, access: .routerPrivate)))
        case let .hosting(world, .internet) where !cloud.allowsInternetPlay:
            start(ActiveSession(mode: .hosting(world, access: .routerPublic)))
        case .cloud where !settings.parental.allowJoiningRooms:
            refuse(L("Joining other people's rooms is turned off in Settings → Family."))
        default:
            start(active)
        }
    }

    /// Why a game cannot start, once the sheet it was started from has gone:
    /// an alert over a sheet on its way out is never seen.
    private func refuse(_ message: String) {
        PresentationQueue.whenClear { blockedMessage = message }
    }

    /// The game covers the whole screen only when nothing else is up: most
    /// ways in are buttons inside a sheet that is still leaving when they
    /// call this. A second tap while waiting is ignored.
    private func start(_ active: ActiveSession) {
        guard activeSession == nil, !startingSession else { return }
        startingSession = true
        summaryStart = settings.summarySnapshot(worldsMade: store.entries.count, pictures: ScreenshotStore.all().count)
        lastMode = active.mode
        rememberLastPlayed(active.mode)
        friendNearby = nil
        PresentationQueue.whenClear {
            startingSession = false
            activeSession = active
        }
    }

    /// One of this iPad's worlds, for Carry on. A game from the list is
    /// remembered by its page, which knows its listing.
    private func rememberLastPlayed(_ mode: ActiveSession.Mode) {
        switch mode {
        case let .solo(world), let .hosting(world, _):
            if store.entries.contains(where: { $0.id == world.id }) {
                settings.memory.lastPlayed = LastPlayed(kind: .world, id: world.id.uuidString, title: world.name)
            }
        default:
            break
        }
    }

    /// How the game went, once it has gone — unless it was only a peek.
    private func showSummary() {
        guard let before = summaryStart else { return }
        summaryStart = nil
        let after = settings.summarySnapshot(worldsMade: store.entries.count, pictures: ScreenshotStore.all().count)
        let result = SessionSummary(game: lastGameName, before: before, after: after)
        let levelUp = settings.claimLevelRewards(worldsMade: store.entries.count, pictures: ScreenshotStore.all().count)
        let badgeCoins = settings.claimBadgeRewards(worldsMade: store.entries.count, pictures: ScreenshotStore.all().count)
        guard result.isWorthShowing || levelUp != nil || badgeCoins != nil else { return }
        // Joining again by code or invitation may not work a second time;
        // Play again is for games started here.
        var again: ActiveSession.Mode?
        switch lastMode {
        case .solo?, .hosting?: again = lastMode
        default: again = nil
        }
        summary = SummaryCard(summary: result, mode: again, levelUp: levelUp.map { LevelUp(level: $0.level, coins: $0.coins) },
                              badgeCoins: badgeCoins)
    }

    private func playAgain(_ card: SummaryCard) -> (() -> Void)? {
        guard let mode = card.mode else { return nil }
        return { enter(ActiveSession(mode: mode)) }
    }

    /// A friend in a room nearby, said once per room.
    private func noticeFriends(in peers: [DiscoveredPeer]) {
        guard settings.parental.allowJoiningRooms else { return }
        let friends = settings.social.friends.map(\.id)
        guard !friends.isEmpty else { return }
        let rooms = peers.filter { $0.isCompatible && !$0.isFull && !$0.isStudioSession }.map { (id: $0.id, tag: $0.people) }
        // Noted during a game too, so coming back from playing with a friend
        // does not announce the room just left.
        let seen = sightings.newlySeen(rooms: rooms, friends: friends)
        guard activeSession == nil, !startingSession, let first = seen.first,
              let peer = peers.first(where: { $0.id == first.roomID }),
              let friend = settings.social.friends.first(where: { $0.id == first.friend }) else { return }
        withAnimation { friendNearby = FriendNearby(peer: peer, name: friend.shownName) }
    }

    /// Straight in to a public room; a private one needs its code, typed on
    /// Play → Rooms.
    private func joinFriend(_ peer: DiscoveredPeer) {
        friendNearby = nil
        if let code = peer.publicCode {
            enter(ActiveSession(mode: .joining(peer, code: code)))
        } else {
            playSection = .rooms
            selectedTab = .play
        }
    }

    /// Backs everything up first — a copy stays inside the app too — then
    /// shows how to hand the new version over.
    private func beginInstall() {
        installing = UpdateInstall(backup: saves.makeBackupBeforeUpdate(settings: settings, worlds: store))
    }
}

/// The card after a game.
struct SummaryCard: Identifiable {
    let id = UUID()
    let summary: SessionSummary
    /// How to play again, when that makes sense.
    let mode: ActiveSession.Mode?
    /// A level reached on the way, and its coins.
    var levelUp: LevelUp?
    /// Coins for badges earned on the way.
    var badgeCoins: Int?
}

struct LevelUp: Hashable {
    let level: Int
    let coins: Int
}

/// A friend seen in a room nearby.
struct FriendNearby: Equatable {
    let peer: DiscoveredPeer
    let name: String
}

/// A downloaded update about to be handed over, with the backup made for it.
struct UpdateInstall: Identifiable {
    let id = UUID()
    let backup: URL?
}

/// What the player is about to enter, so `PlayScreen` knows whether it is
/// hosting, joining, or playing alone.
public struct ActiveSession: EqualByID {
    /// `indirect`: each case's value lives in a box of its own. A whole
    /// world kept inline made every copy of the screens that hold a session
    /// copy the world field by field, and the code for those copies was a
    /// third of what the compiler made for the main menu.
    public indirect enum Mode: Equatable {
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
}
