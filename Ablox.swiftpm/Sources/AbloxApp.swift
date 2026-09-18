import SwiftUI

@main
struct AbloxApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var session: SessionCoordinator
    @StateObject private var store = ProjectStore()

    init() {
        // `AppSettings` owns the persisted peer identity, so it must exist
        // before the session that uses it. StateObject's autoclosure runs
        // once, which is what keeps this from re-minting an identity on
        // every re-render.
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _session = StateObject(wrappedValue: SessionCoordinator(
            localPeerID: settings.peerID,
            profile: settings.profile
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(store)
        }
    }
}
