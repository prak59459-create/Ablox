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

        if let stored = defaults.string(forKey: Key.peerID), let uuid = UUID(uuidString: stored) {
            self.peerID = PeerID(uuid)
        } else {
            let fresh = PeerID()
            defaults.set(fresh.raw.uuidString, forKey: Key.peerID)
            self.peerID = fresh
        }

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

    public func resetToDefaults() {
        movement = .default
        joystickOnRight = false
        invertCameraY = false
        cameraSensitivity = 1.0
        soundEnabled = true
        hapticsEnabled = true
    }
}

#if canImport(UIKit)
import UIKit
#endif
