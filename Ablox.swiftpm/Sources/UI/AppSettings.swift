import Foundation
import Combine

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
        let coins = CoinRate.coins(forScore: score, completedRound: completedRound)
        wallet.earn(coins)
        coinLedger.record(coins, reason: game.isEmpty ? L("A round") : game)
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
        ChatModerator(isFilterEnabled: chatFilterEnabled)
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

#if canImport(UIKit)
import UIKit
#endif
