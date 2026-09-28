import Foundation
import Combine
import AbloxCore

/// Everything that survives a relaunch and is not a world.
///
/// Stored in `UserDefaults` rather than a file: it is a handful of small
/// values, and `UserDefaults` already handles the "first launch, nothing
/// saved" case that a file-based store would have to special-case.
@MainActor
public final class AppSettings: ObservableObject {

    private enum Key {
        static let profile = "ablox.profile"
        static let peerID = "ablox.peerID"
        static let movement = "ablox.movement"
        static let joystickOnRight = "ablox.joystickOnRight"
        static let invertCameraY = "ablox.invertCameraY"
        static let cameraSensitivity = "ablox.cameraSensitivity"
        static let soundEnabled = "ablox.soundEnabled"
        static let hapticsEnabled = "ablox.hapticsEnabled"
        static let wallet = "ablox.wallet"
        static let muteList = "ablox.muteList"
        static let chatFilterEnabled = "ablox.chatFilterEnabled"
        static let language = "ablox.language"
        static let catalogue = "ablox.catalogueRepository"
        static let catalogueBranch = "ablox.catalogueBranch"
        static let graphicsQuality = "ablox.graphicsQuality"
        static let showFrameRate = "ablox.showFrameRate"
        static let parental = "ablox.parental"
        static let playtime = "ablox.playtime"
        static let ledger = "ablox.coinLedger"
        static let preferences = "ablox.playPreferences"
        static let memory = "ablox.menuMemory"
        static let social = "ablox.social"
        static let cloud = "ablox.cloud"
    }

    private let defaults: UserDefaults

    @Published public var profile: AvatarProfile {
        didSet { persist(profile, forKey: Key.profile) }
    }

    @Published public var movement: MovementConfig {
        didSet { persist(movement, forKey: Key.movement) }
    }

    /// Left-handed players move the stick to the right side.
    @Published public var joystickOnRight: Bool {
        didSet { defaults.set(joystickOnRight, forKey: Key.joystickOnRight) }
    }

    @Published public var invertCameraY: Bool {
        didSet { defaults.set(invertCameraY, forKey: Key.invertCameraY) }
    }

    @Published public var cameraSensitivity: Double {
        didSet { defaults.set(cameraSensitivity, forKey: Key.cameraSensitivity) }
    }

    @Published public var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    @Published public var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    /// Coins and unlocked items. Local and per-device — there is no server to
    /// hold a balance, and trusting a peer's claim about its own coins would
    /// make the first child who reads the protocol very rich.
    @Published public var wallet: PlayerWallet {
        didSet { persist(wallet, forKey: Key.wallet) }
    }

    /// Who this device has chosen not to hear from. Never leaves the iPad.
    @Published public var muteList: MuteList {
        didSet { persist(muteList, forKey: Key.muteList) }
    }

    /// Whether the chat word filter is applied. Muting works either way.
    @Published public var chatFilterEnabled: Bool {
        didSet { defaults.set(chatFilterEnabled, forKey: Key.chatFilterEnabled) }
    }

    /// English, Japanese, or whatever the iPad is set to.
    ///
    /// Applying it writes a global that every `L(...)` reads, including the
    /// ones in the portable core that have no SwiftUI to reach into. SwiftUI
    /// does not observe that global, so `AbloxApp` hangs `.id(language)` on
    /// the view below its state objects: changing the language rebuilds the
    /// interface once, and the session, wallet and settings survive it.
    @Published public var language: LanguagePreference {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            applyLanguage()
        }
    }

    /// Pushes the current preference into the global the whole app reads.
    ///
    /// `Locale.preferredLanguages` rather than `Locale.current`: the first is
    /// the ordered list the person actually chose in Settings, and the second
    /// answers with a region even for a language the app does not have.
    public func applyLanguage() {
        Localization.language = language.language(preferredCodes: Locale.preferredLanguages)
    }

    /// Which GitHub repository the Games tab reads.
    ///
    /// Settable so a school or a club can run its own list instead of the
    /// shared one. Only the `owner/repo` part is stored, and `CatalogueSource`
    /// refuses anything that is not two plausible GitHub names — so this can
    /// never become an arbitrary URL the app fetches from.
    @Published public var catalogueRepository: String {
        didSet { defaults.set(catalogueRepository, forKey: Key.catalogue) }
    }

    /// Which branch of that repository. A list can be tried out on a branch
    /// before it goes to `main` and everyone's iPad.
    @Published public var catalogueBranch: String {
        didSet { defaults.set(catalogueBranch, forKey: Key.catalogueBranch) }
    }

    /// Settings → Graphics. Auto by default: it starts high and steps down
    /// by itself when a big world would otherwise drop below 30 fps.
    @Published public var graphicsQuality: GraphicsQuality {
        didSet { defaults.set(graphicsQuality.rawValue, forKey: Key.graphicsQuality) }
    }

    /// A small frame-rate counter while playing.
    @Published public var showFrameRate: Bool {
        didSet { defaults.set(showFrameRate, forKey: Key.showFrameRate) }
    }

    /// Settings → Family: limits, bedtime, chat and the passcode that guards
    /// them. See `ParentalControls`.
    @Published public var parental: ParentalControls {
        didSet { persist(parental, forKey: Key.parental) }
    }

    /// How long was played, per day and per game.
    @Published public var playtime: PlaytimeLog {
        didSet { persist(playtime, forKey: Key.playtime) }
    }

    /// Every coin in and out, for the history screen and the spending limit.
    @Published public var coinLedger: CoinLedger {
        didSet { persist(coinLedger, forKey: Key.ledger) }
    }

    /// Comfort, eyes, battery, text size and the play screen's extras.
    @Published public var preferences: PlayPreferences {
        didSet { persist(preferences, forKey: Key.preferences) }
    }

    /// Everything the menus remember: wishlist, outfits, favourite games,
    /// notes, what has been seen, save slots… See `MenuMemory`.
    @Published public var memory: MenuMemory {
        didSet { persist(memory, forKey: Key.memory) }
    }

    /// Friends, people played with lately, and people blocked.
    @Published public var social: SocialBook {
        didSet { persist(social, forKey: Key.social) }
    }

    /// Settings → Family → Internet.
    @Published public var cloud: CloudSettings {
        didSet { persist(cloud, forKey: Key.cloud) }
    }

    /// The validated source, falling back to the built-in list if someone has
    /// typed something unusable into Settings.
    public var catalogueSource: CatalogueSource {
        CatalogueSource.chosen(repository: catalogueRepository, branch: catalogueBranch)
    }

    /// This device's identity, generated once and kept. Stable across launches
    /// so a player's score and avatar survive a reconnect mid-session.
    public let peerID: PeerID

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // A missing or corrupt value must not stop the app launching — fall
        // back to the default and move on.
        self.profile = AppSettings.decode(AvatarProfile.self, from: defaults, key: Key.profile) ?? .default
        self.movement = AppSettings.decode(MovementConfig.self, from: defaults, key: Key.movement) ?? .default

        self.joystickOnRight = defaults.object(forKey: Key.joystickOnRight) as? Bool ?? false
        self.invertCameraY = defaults.object(forKey: Key.invertCameraY) as? Bool ?? false
        self.cameraSensitivity = defaults.object(forKey: Key.cameraSensitivity) as? Double ?? 1.0
        self.soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true

        self.wallet = AppSettings.decode(PlayerWallet.self, from: defaults, key: Key.wallet) ?? PlayerWallet()
        self.muteList = AppSettings.decode(MuteList.self, from: defaults, key: Key.muteList) ?? MuteList()
        // Filtering defaults on. Someone who wants it off can say so; someone
        // who never opens Settings should get the safer behaviour.
        self.chatFilterEnabled = defaults.object(forKey: Key.chatFilterEnabled) as? Bool ?? true

        // Nothing saved means a first launch, which should look like the rest
        // of the iPad rather than like an American default.
        self.language = defaults.string(forKey: Key.language)
            .flatMap(LanguagePreference.init(rawValue:)) ?? .system

        self.catalogueRepository = defaults.string(forKey: Key.catalogue)
            ?? CatalogueSource.default.repository
        self.catalogueBranch = defaults.string(forKey: Key.catalogueBranch)
            ?? CatalogueSource.default.reference

        self.graphicsQuality = defaults.string(forKey: Key.graphicsQuality)
            .flatMap(GraphicsQuality.init(rawValue:)) ?? .auto
        self.showFrameRate = defaults.object(forKey: Key.showFrameRate) as? Bool ?? false
        self.parental = AppSettings.decode(ParentalControls.self, from: defaults, key: Key.parental) ?? ParentalControls()
        self.playtime = AppSettings.decode(PlaytimeLog.self, from: defaults, key: Key.playtime) ?? PlaytimeLog()
        self.coinLedger = AppSettings.decode(CoinLedger.self, from: defaults, key: Key.ledger) ?? CoinLedger()
        self.preferences = AppSettings.decode(PlayPreferences.self, from: defaults, key: Key.preferences) ?? PlayPreferences()
        self.memory = AppSettings.decode(MenuMemory.self, from: defaults, key: Key.memory) ?? MenuMemory()
        self.social = AppSettings.decode(SocialBook.self, from: defaults, key: Key.social) ?? SocialBook()
        self.cloud = AppSettings.decode(CloudSettings.self, from: defaults, key: Key.cloud) ?? CloudSettings()

        if let stored = defaults.string(forKey: Key.peerID), let uuid = UUID(uuidString: stored) {
            self.peerID = PeerID(uuid)
        } else {
            let fresh = PeerID()
            defaults.set(fresh.raw.uuidString, forKey: Key.peerID)
            self.peerID = fresh
        }

        // Before anything reads a string. `didSet` does not run during init,
        // so the stored preference has to be applied by hand here or the first
        // screen draws in English and only corrects itself when someone opens
        // Settings.
        applyLanguage()

        // First launch: give the player a name and a look rather than a
        // screen full of defaults called "Player".
        if self.profile.displayName.isEmpty || self.profile == .default {
            var generated = AvatarProfile.generated(for: peerID, name: AppSettings.suggestedName())
            generated.displayName = AppSettings.suggestedName()
            self.profile = generated
        }
    }

    // MARK: Persistence

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Something friendlier than "Player" out of the box.
    private static func suggestedName() -> String {
        #if canImport(UIKit)
        let deviceName = UIDevice.current.name
        // "Taro's iPad" → "Taro". Device names are localised, so this is a
        // best-effort tidy-up, not a parser.
        if let cut = deviceName.range(of: "'s ") {
            return String(deviceName[..<cut.lowerBound])
        }
        if !deviceName.isEmpty, deviceName != "iPad" { return deviceName }
        #endif
        return "Builder"
    }

    /// Banks a round's score as coins. Called when a round ends.
    public func award(score: Int, completedRound: Bool, game: String = "") {
        if !game.isEmpty, score > (memory.bestScores[game] ?? 0) { memory.bestScores[game] = score }
        let coins = CoinRate.coins(forScore: score, completedRound: completedRound)
        wallet.earn(coins)
        coinLedger.record(coins, reason: game.isEmpty ? L("A round") : game)
        mission(.earnCoins, amount: coins)
    }

    // MARK: Today's missions

    public var today: String { PlaytimeLog.dayKey(Date()) }

    /// Counts towards today's missions; returns the ones this finished, to
    /// say so while playing.
    @discardableResult
    public func mission(_ kind: MissionKind, amount: Int = 1) -> [Mission] {
        finished { $0.record(kind, amount: amount, on: $1) }
    }

    /// A game started today, for "different games".
    @discardableResult
    public func missionGame(_ game: String) -> [Mission] {
        finished { $0.played(game: game, on: $1) }
    }

    private func finished(_ change: (inout MissionBook, String) -> Void) -> [Mission] {
        let day = today
        let before = memory.missions.done(on: day)
        change(&memory.missions, day)
        let after = memory.missions.done(on: day)
        guard after != before else { return [] }
        return memory.missions.missions(on: day).filter { after.contains($0.id) && !before.contains($0.id) }
    }

    /// The reward for a finished mission, into the wallet; nil when there
    /// is none to take.
    @discardableResult
    public func claim(_ mission: Mission) -> Int? {
        guard let coins = memory.missions.claim(mission, on: today) else { return nil }
        give(coins: coins, reason: L("Mission: {}", mission.title))
        memory.counters.missionsClaimed += 1
        return coins
    }

    /// What the card after a game compares.
    public func summarySnapshot(worldsMade: Int, pictures: Int) -> SessionSummary.Snapshot {
        SessionSummary.Snapshot(
            lifetimeCoins: wallet.lifetimeEarned,
            missionsDone: memory.missions.done(on: today),
            badges: Set(Achievement.earned(progressStats(worldsMade: worldsMade, pictures: pictures)).map(\.rawValue))
        )
    }

    /// Coins from somewhere other than a round — a daily bonus, a gift.
    public func give(coins: Int, reason: String) {
        guard coins > 0 else { return }
        wallet.earn(coins)
        coinLedger.record(coins, reason: reason)
    }

    /// Buys from the shop, within today's spending limit.
    public func buy(_ item: ShopItem) -> PlayerWallet.PurchaseResult? {
        if !wallet.owns(item), !item.isFree,
           !coinLedger.allows(spending: item.price, limit: parental.dailyCoinLimit) {
            return nil
        }
        let result = wallet.purchase(item.id)
        if result.succeeded, !item.isFree { coinLedger.record(-item.price, reason: item.displayName) }
        return result
    }

    /// Today's coins for coming back, if not yet given — added to the wallet
    /// and returned so the menu can say so.
    public func claimDailyBonus() -> Int? {
        guard let coins = memory.dailyBonus.claim() else { return nil }
        memory.bestStreak = max(memory.bestStreak, memory.dailyBonus.streak)
        give(coins: coins, reason: L("Daily bonus"))
        return coins
    }

    /// Blocks a player: never a friend, never heard. Their chat stays
    /// hidden until they are unblocked.
    public func block(_ id: PeerID, name: String) {
        social.block(id, name: name)
        muteList.mute(id)
    }

    public func unblock(_ id: PeerID) {
        social.unblock(id)
        muteList.unmute(id)
    }

    /// Everything the badges look at.
    public func progressStats(worldsMade: Int, pictures: Int) -> ProgressStats {
        var stats = ProgressStats(
            gamesPlayed: playtime.timesPlayed.count,
            totalMinutes: Int(playtime.totalSeconds.values.reduce(0, +) / 60),
            daysPlayed: playtime.days.filter { $0.seconds > 0 }.count,
            lifetimeCoins: wallet.lifetimeEarned,
            itemsOwned: wallet.ownedItemIDs.count,
            pictures: pictures,
            worldsMade: worldsMade,
            hasPet: ShopCatalogue.items(of: .pet).contains { $0.pet != AvatarProfile.Pet.none && wallet.owns($0) },
            bestStreak: memory.bestStreak
        )
        func owned(_ kind: ShopItem.Kind) -> Int { wallet.ownedItems(of: kind).filter { !$0.isFree }.count }
        stats.counters = memory.counters
        stats.hatsOwned = owned(.hat)
        stats.petsOwned = owned(.pet)
        stats.trailsOwned = owned(.trail)
        stats.aurasOwned = owned(.aura)
        stats.friends = social.friends.count
        stats.gamesLiked = memory.gameNotes.values.filter(\.liked).count
        stats.outfitsSaved = memory.outfits.compactMap { $0 }.count
        stats.mostPlaysOfOneGame = playtime.timesPlayed.values.max() ?? 0
        return stats
    }

    /// Coins for every level reached since the last look; the new level and
    /// the coins, or nil when there is nothing new.
    public func claimLevelRewards(worldsMade: Int, pictures: Int) -> (level: Int, coins: Int)? {
        let level = progressStats(worldsMade: worldsMade, pictures: pictures).level.number
        guard level > memory.rewardedLevel else { return nil }
        let coins = ((memory.rewardedLevel + 1)...level).reduce(0) { $0 + PlayerLevel.reward(for: $1) }
        memory.rewardedLevel = level
        give(coins: coins, reason: L("Level {}", level))
        return (level, coins)
    }

    /// An emote or stamp sent, for the badges that count them.
    public func noteGesture(_ gesture: Gesture) {
        switch gesture {
        case .emote: memory.counters.emotes += 1
        case .stamp: memory.counters.stamps += 1
        }
    }

    /// Whether a game may start now, and if not, why.
    public var playVerdict: PlayGate.Verdict {
        PlayGate.verdict(parental, log: playtime)
    }

    /// Adds time just played to today and to the game.
    public func recordPlay(seconds: Double, game: String) {
        playtime.add(seconds: seconds, game: game, at: Date())
    }

    /// The moderator built from current preferences.
    public var chatModerator: ChatModerator {
        ChatModerator(additionalTerms: parental.extraBlockedWords ?? [], isFilterEnabled: chatFilterEnabled,
                      strict: parental.strictChatFilter ?? false)
    }

    public func resetToDefaults() {
        movement = .default
        joystickOnRight = false
        invertCameraY = false
        cameraSensitivity = 1.0
        soundEnabled = true
        hapticsEnabled = true
        graphicsQuality = .auto
        showFrameRate = false
        preferences = PlayPreferences()
    }
}

// MARK: - What the menus remember

/// The last game played, to carry on with from the Play tab.
public struct LastPlayed: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// One of this iPad's own worlds, by world id.
        case world
        /// A game from the list, by listing id.
        case catalogue
    }

    public var kind: Kind
    public var id: String
    public var title: String
    public var at: Date

    public init(kind: Kind, id: String, title: String, at: Date = Date()) {
        self.kind = kind
        self.id = id
        self.title = title
        self.at = at
    }
}

/// A player's own note on a game: liked, and a few words.
public struct GameNote: Codable, Hashable, Sendable {
    public var liked = false
    public var memo = ""
    public init() {}
}

/// The menus' memory, in one piece so a new field is one line here.
public struct MenuMemory: Codable, Hashable, Sendable {
    /// Shop items wanted, by id.
    public var wishlist: Set<String> = []
    /// Three saved looks.
    public var outfits: [AvatarProfile?] = [nil, nil, nil]
    public var dailyBonus = DailyBonus()
    public var bestStreak = 0
    /// Catalogue games, by listing id.
    public var favoriteGames: Set<String> = []
    /// Newest first.
    public var recentGames: [String] = []
    public var gameNotes: [String: GameNote] = [:]
    /// The revision each game had when last seen, for "new" and "updated".
    public var seenGames: [String: String] = [:]
    /// More game lists to switch between, as "owner/repo".
    public var extraCatalogues: [String] = []
    /// Which save slot each world plays with, by world id.
    public var saveSlots: [String: Int] = [:]
    /// A folder chosen in Files for automatic backups.
    public var autoBackupBookmark: Data?
    public var lastAutoBackup: Date?
    /// Today's three missions and how far along they are.
    public var missions = MissionBook()
    /// Games put out of sight in the Games tab, by listing id.
    public var hiddenGames: Set<String> = []
    public var recentSearches = RecentSearches()
    public var gameSort: GameSort = .suggested
    /// The shop item being saved up for.
    public var savingsGoal: String?
    /// The last game played, for "Carry on" on the Play tab.
    public var lastPlayed: LastPlayed?
    /// Favourite emotes (first in the list, keys 1 to 4) and the one for
    /// winning.
    public var emotes = EmoteFavourites()
    /// Emotes, stamps, wins… counted for badges and levels.
    public var counters = LifetimeCounters()
    /// Chat phrases of the player's own.
    public var phrases = SavedPhrases()
    // The Games tab (see GameShelves.swift).
    public var ratings = GameRatings()
    /// Games to play later, first added first.
    public var playLater: [String] = []
    public var collections = GameCollections()
    public var viewedGames = RecentlyViewed()
    /// When each game was last started, by id.
    public var lastPlayedAt: [String: Date] = [:]
    /// The best score in each game, by name.
    public var bestScores: [String: Int] = [:]
    public var gamesLayout: GamesLayout = .bigCards
    /// The highest level whose coins have been given.
    public var rewardedLevel = 1

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wishlist = (try? c.decodeIfPresent(Set<String>.self, forKey: .wishlist)) ?? []
        outfits = (try? c.decodeIfPresent([AvatarProfile?].self, forKey: .outfits)) ?? [nil, nil, nil]
        while outfits.count < 3 { outfits.append(nil) }
        dailyBonus = (try? c.decodeIfPresent(DailyBonus.self, forKey: .dailyBonus)) ?? DailyBonus()
        bestStreak = (try? c.decodeIfPresent(Int.self, forKey: .bestStreak)) ?? 0
        favoriteGames = (try? c.decodeIfPresent(Set<String>.self, forKey: .favoriteGames)) ?? []
        recentGames = (try? c.decodeIfPresent([String].self, forKey: .recentGames)) ?? []
        gameNotes = (try? c.decodeIfPresent([String: GameNote].self, forKey: .gameNotes)) ?? [:]
        seenGames = (try? c.decodeIfPresent([String: String].self, forKey: .seenGames)) ?? [:]
        extraCatalogues = (try? c.decodeIfPresent([String].self, forKey: .extraCatalogues)) ?? []
        saveSlots = (try? c.decodeIfPresent([String: Int].self, forKey: .saveSlots)) ?? [:]
        autoBackupBookmark = try? c.decodeIfPresent(Data.self, forKey: .autoBackupBookmark)
        lastAutoBackup = try? c.decodeIfPresent(Date.self, forKey: .lastAutoBackup)
        missions = (try? c.decodeIfPresent(MissionBook.self, forKey: .missions)) ?? MissionBook()
        hiddenGames = (try? c.decodeIfPresent(Set<String>.self, forKey: .hiddenGames)) ?? []
        recentSearches = (try? c.decodeIfPresent(RecentSearches.self, forKey: .recentSearches)) ?? RecentSearches()
        gameSort = (try? c.decodeIfPresent(GameSort.self, forKey: .gameSort)) ?? .suggested
        savingsGoal = try? c.decodeIfPresent(String.self, forKey: .savingsGoal)
        lastPlayed = try? c.decodeIfPresent(LastPlayed.self, forKey: .lastPlayed)
        emotes = (try? c.decodeIfPresent(EmoteFavourites.self, forKey: .emotes)) ?? EmoteFavourites()
        counters = (try? c.decodeIfPresent(LifetimeCounters.self, forKey: .counters)) ?? LifetimeCounters()
        phrases = (try? c.decodeIfPresent(SavedPhrases.self, forKey: .phrases)) ?? SavedPhrases()
        ratings = (try? c.decodeIfPresent(GameRatings.self, forKey: .ratings)) ?? GameRatings()
        playLater = (try? c.decodeIfPresent([String].self, forKey: .playLater)) ?? []
        collections = (try? c.decodeIfPresent(GameCollections.self, forKey: .collections)) ?? GameCollections()
        viewedGames = (try? c.decodeIfPresent(RecentlyViewed.self, forKey: .viewedGames)) ?? RecentlyViewed()
        lastPlayedAt = (try? c.decodeIfPresent([String: Date].self, forKey: .lastPlayedAt)) ?? [:]
        bestScores = (try? c.decodeIfPresent([String: Int].self, forKey: .bestScores)) ?? [:]
        gamesLayout = (try? c.decodeIfPresent(GamesLayout.self, forKey: .gamesLayout)) ?? .bigCards
        rewardedLevel = (try? c.decodeIfPresent(Int.self, forKey: .rewardedLevel)) ?? 1
    }

    /// Puts a game at the front of "recently played".
    public mutating func played(_ gameID: String) {
        recentGames.removeAll { $0 == gameID }
        recentGames.insert(gameID, at: 0)
        if recentGames.count > 20 { recentGames.removeLast(recentGames.count - 20) }
        lastPlayedAt[gameID] = Date()
        if lastPlayedAt.count > 300, let oldest = lastPlayedAt.min(by: { $0.value < $1.value }) {
            lastPlayedAt[oldest.key] = nil
        }
        // Played: no longer waiting to be played later.
        playLater.removeAll { $0 == gameID }
    }

    /// A game on (or off) the "play later" list.
    public mutating func togglePlayLater(_ gameID: String) {
        if let index = playLater.firstIndex(of: gameID) {
            playLater.remove(at: index)
        } else {
            playLater.append(gameID)
            if playLater.count > 100 { playLater.removeFirst(playLater.count - 100) }
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
