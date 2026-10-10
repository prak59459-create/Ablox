import SwiftUI
import AbloxCore

@main
struct AbloxApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var session: SessionCoordinator
    @StateObject private var store = ProjectStore()
    @StateObject private var saves: GameSaves
    @StateObject private var updater = AppUpdater(release: AppRelease.current)
    /// Friends, chat and rooms over the internet — off until a grown-up
    /// allows it (Settings → Family → Internet).
    @StateObject private var cloud = CloudService()
    /// Messages for the main menu from the repository (`notices.json`).
    @StateObject private var notices = NoticeService(release: AppRelease.current)
    /// Settings → Look: the accent colour, which also rebuilds the views.
    @AppStorage(AbloxAccent.key) private var accent = AbloxAccent.cyan.rawValue
    @Environment(\.scenePhase) private var scenePhase

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
        // Before anything else: notices a crash last time and watches this run.
        ProblemRecorder.shared.start(app: "Ablox")
        ProblemRecorder.shared.noteActivity("Starting")
        // Sounds a game names come from the same place as the game list.
        SoundLibraryStore.shared.source = settings.catalogueSource
    }

    var body: some Scene {
        WindowGroup {
            watching(menus)
        }
    }

    private var menus: some View {
        MainMenuView()
            .environmentObject(settings)
            .environmentObject(session)
            .environmentObject(store)
            .environmentObject(saves)
            .environmentObject(updater)
            .environmentObject(cloud)
            .environmentObject(notices)
            // Settings → Comfort → Text size, for the whole app.
            .dynamicTypeSize(settings.preferences.textSize.dynamicType)
    }

    /// Rebuilds the interface when the language changes.
    ///
    /// `L(...)` reads a global that SwiftUI knows nothing about, so nothing
    /// would redraw on its own. Changing the identity here forces one full
    /// rebuild — deliberately *below* the state objects above, so the
    /// session, wallet and settings are not recreated with it. It resets
    /// view-local state such as the open tab, which is acceptable for
    /// something that happens once in a while and arguably wanted.
    private var interfaceIdentity: String {
        "\(settings.language.rawValue)-\(accent)"
    }

    private func watching<Content: View>(_ content: Content) -> some View {
        content
            .id(interfaceIdentity)
            // Offers Ablox's own keyboard on an iPad where the system one
            // does not come up.
            .onAppear { KeyboardController.shared.startWatching() }
            // Going to the background is not a crash.
            .onChange(of: scenePhase) { _, phase in
                ProblemRecorder.shared.markRunning(phase != .background)
            }
    }
}
