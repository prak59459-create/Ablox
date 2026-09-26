import SwiftUI

@main
struct AbloxApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var session: SessionCoordinator
    @StateObject private var store = ProjectStore()
    @StateObject private var saves: GameSaves
    @StateObject private var updater = AppUpdater(release: AppRelease.current)

    init() {
        // `AppSettings` owns the persisted peer identity, so it must exist
        // before the session that uses it. StateObject's autoclosure runs
        // once, which is what keeps this from re-minting an identity on
        // every re-render.
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        let session = SessionCoordinator(
            localPeerID: settings.peerID,
            profile: settings.profile
        )
        // Games played here keep their progress on this iPad.
        let saves = GameSaves()
        session.saveStore = saves.store
        _session = StateObject(wrappedValue: session)
        _saves = StateObject(wrappedValue: saves)
    }

    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(store)
                .environmentObject(saves)
                .environmentObject(updater)
                // Rebuilds the interface when the language changes.
                //
                // `L(...)` reads a global that SwiftUI knows nothing about, so
                // nothing would redraw on its own. Changing the identity here
                // forces one full rebuild — deliberately *below* the state
                // objects above, so the session, wallet and settings are not
                // recreated with it. It resets view-local state such as the
                // open tab, which is acceptable for something that happens
                // once in a while and arguably wanted.
                .id(settings.language)
        }
    }
}
