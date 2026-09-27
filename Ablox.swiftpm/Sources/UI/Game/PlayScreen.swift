import SwiftUI
import AbloxCore

/// The full-screen play surface: 3D viewport underneath, HUD on top.
public struct PlayScreen: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var cloud: CloudService
    @Environment(\.scenePhase) private var scenePhase

    let activeSession: ActiveSession
    let onExit: () -> Void

    @State private var stick: Vec3 = .zero
    @State private var isJumping = false
    @State private var isRunning = false
    @State private var cameraYaw: Float = 0
    @State private var cameraPitch: Float = -14
    @State private var showScoreboard = false
    @State private var showChat = false
    @State private var chatDraft = ""
    @State private var hasBankedThisRound = false
    @State private var isFiring = false

    // Settings → Family, while playing.
    @State private var sessionSeconds: Double = 0
    @State private var lastRestReminder: Double = 0
    @State private var countedStart = false
    @State private var showingRest = false
    /// Seconds until the game closes, once today's time or quiet hours
    /// have come — a minute's warning rather than the world vanishing.
    @State private var closingIn: Int?
    private let playClock = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    // The play screen's extras (see PlayExtras.swift).
    @StateObject private var clips = ClipRecorder()
    @State private var link = ViewportLink()
    @State private var showEmotes = false
    @State private var mapExpanded = false
    @State private var showMenu = false
    @State private var photoMode = false
    @State private var photoFilter: PhotoFilter = .none
    @State private var preferFirstPerson = false
    @State private var spectating: PeerID?
    @State private var editingButtons = false
    @State private var sharing: SharedFile?
    @State private var toast: String?
    @State private var zoomAtPinchStart: Float?
    /// Whether this visit has already taken the world's picture for the list.
    @State private var tookThumbnail = false
    /// Who was here at the last look, to notice arrivals.
    @State private var knownPeople: Set<PeerID> = []
    @State private var choosingHowToLeave = false
    /// The player's own timer, from the pause menu.
    @State private var selfTimer = SelfTimer()
    /// Whether "play with someone else" was counted this visit.
    @State private var countedTogether = false
    /// A game controller, keyboard or mouse, beside the touch controls.
    @StateObject private var hardware = HardwareInput()

    public init(session: SessionCoordinator, activeSession: ActiveSession, onExit: @escaping () -> Void) {
        self.session = session
        self.activeSession = activeSession
        self.onExit = onExit
    }

    /// First person may look well up and down; the orbit camera may not go
    /// under the floor.
    private var pitchRange: ClosedRange<Float> {
        if photoMode { return -85...60 }
        return isFirstPerson ? -80...80 : -75...20
    }

    private var isFirstPerson: Bool {
        session.scripted.camera.mode == .firstPerson
            || (session.scripted.camera.mode == .thirdPerson && preferFirstPerson && spectating == nil)
    }

    private var movementInput: MovementInput {
        MovementInput(stick: stick == .zero ? hardware.stick : stick,
                      isJumping: isJumping || hardware.jumping,
                      isRunning: isRunning || hardware.running,
                      cameraYawDegrees: cameraYaw)
    }

    // In pieces, each type-checked on its own: as one expression the play
    // screen was among the slowest things in the app to compile.
    public var body: some View {
        reactions(lifecycle(screen))
    }

    private var screen: some View {
        ZStack {
            viewport
            comfortFilters
            if photoMode {
                photoLayer
            } else {
                playLayers
            }
            if let toast {
                toastView(toast)
            }
            statusOverlays
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // The game is always dark, whatever the menus are set to: its buttons
        // sit over the 3D world, not over a page.
        .preferredColorScheme(.dark)
    }

    private var viewport: some View {
        GameViewport(
            session: session,
            input: .constant(movementInput),
            cameraYaw: $cameraYaw,
            cameraPitch: $cameraPitch,
            soundEnabled: settings.soundEnabled,
            hapticsEnabled: settings.hapticsEnabled,
            isFiring: (isFiring || hardware.firing) && session.scripted.weapon != nil,
            graphicsQuality: settings.graphicsQuality,
            showFrameRate: settings.showFrameRate,
            preferences: settings.preferences,
            spectating: spectating,
            preferFirstPerson: preferFirstPerson,
            photoMode: photoMode,
            link: link
        )
        .ignoresSafeArea()
    }

    @ViewBuilder private var comfortFilters: some View {
        // Settings → Comfort: warmer, dimmer, over the game only.
        if settings.preferences.warmScreen {
            Color(red: 1, green: 0.55, blue: 0.2).opacity(0.14)
                .blendMode(.multiply)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        if settings.preferences.dimming > 0 {
            Color.black.opacity(settings.preferences.dimming)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var playLayers: some View {
        // A script can hide the joystick and buttons — a title screen,
        // a cutscene — and the top bar and chat.
        if session.scripted.showsControls && !editingButtons {
            controlsLayer
        }
        ScriptHUDLayer(session: session, reduceFlashing: settings.preferences.reduceFlashing,
                       crosshair: settings.preferences.crosshair, crosshairColor: settings.preferences.crosshairColor)
        PartsHUDLayer(session: session, readAloud: settings.preferences.readLinesAloud)
        hudLayer
        familyNotices
        if !session.isSolo {
            RoomHUD(session: session)
                .padding(.top, 68)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        spectateBar
        if showMenu {
            pauseMenu
        }
        if editingButtons {
            ButtonLayoutEditor(preferences: $settings.preferences, stickOnLeft: !settings.joystickOnRight) {
                editingButtons = false
            }
        }
    }

    private var pauseMenu: some View {
        PauseMenu(
            session: session,
            clips: clips,
            preferFirstPerson: $preferFirstPerson,
            selfTimer: $selfTimer,
            playSeconds: sessionSeconds,
            onResume: closeMenu,
            onScreenshot: { closeMenu(); takePicture() },
            onSaveClip: { closeMenu(); saveClip() },
            onPhotoMode: { closeMenu(); withAnimation { photoMode = true } },
            onReturnToStart: { closeMenu(); link.returnToStart() },
            onEditButtons: { closeMenu(); editingButtons = true },
            onLeave: onExit
        )
        .transition(.opacity)
    }

    @ViewBuilder private var statusOverlays: some View {
        if session.status.isBusy {
            connectingOverlay
        }
        if case let .reconnecting(progress) = session.status {
            reconnectingOverlay(progress)
        }
        if case let .error(message) = session.status {
            errorOverlay(message)
        }
    }

    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                enterSession()
                startHardware()
            }
            .onChange(of: showChat) { _, open in hardware.suspended = open || showMenu }
            .onChange(of: showMenu) { _, open in hardware.suspended = open || showChat }
            .sheet(item: $sharing) { file in
                ActivityShareSheet(items: [file.url])
            }
            .onChange(of: session.roster) { _, roster in
                // Whoever was being watched has gone.
                if let watched = spectating, !roster.contains(where: { $0.peerID == watched }) { spectating = nil }
                noticeWhoIsHere()
            }
            .onReceive(playClock) { _ in countPlay(seconds: 5) }
    }

    private func reactions<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: session.announcement) { _, announcement in
                // The end-of-round banner is the one signal that the round is
                // over for everyone, host or client.
                guard let message = announcement?.message else { return }
                speak(message)
                if message.contains("goal") || message.localizedCaseInsensitiveContains("win") {
                    bankCoins(completed: true)
                }
            }
            // Settings → Problem reports: what went wrong here, kept to send.
            .onChange(of: session.status) { _, status in
                if case let .error(message) = status {
                    ProblemRecorder.shared.record(.network, message, detail: session.world.name)
                }
            }
            .onChange(of: session.scriptLog) { old, new in
                let added = new.filter { line in !old.contains { $0.id == line.id } }
                for line in added where line.isError {
                    ProblemRecorder.shared.record(.script, line.text, detail: session.world.name)
                }
            }
            .onChange(of: session.messageLog) { _, log in
                if let newest = log.last { speak(newest.text) }
            }
            .onDisappear {
                bankCoins(completed: false)
                hardware.stop()
            }
            .onChange(of: scenePhase) { _, phase in
                // Backgrounding is what kills the TCP connection, so returning is
                // the single most likely moment a session needs recovering. Bring
                // any pending attempt forward rather than waiting out a backoff
                // scheduled while the iPad was asleep.
                if phase == .active { session.applicationDidBecomeActive() }
            }
    }

    // MARK: Who is here

    /// Remembers who this player is playing with (Play → Friends), and says
    /// when someone they blocked has come in. Only when someone arrives or
    /// goes — the roster changes with every step anyone takes.
    private func noticeWhoIsHere() {
        let people = session.people
        let ids = Set(people.map(\.peerID))
        guard ids != knownPeople else { return }
        let arrived = ids.subtracting(knownPeople)
        knownPeople = ids
        guard !session.isSolo else { return }
        settings.social.met(people, game: session.world.name, localPeerID: session.localPeerID)
        if arrived.contains(where: { settings.social.isBlocked($0) }) {
            showToast(L("Someone you blocked is in this room. You won't see what they say."))
        } else if let friend = people.first(where: { arrived.contains($0.peerID) && settings.social.isFriend($0.peerID) }) {
            showToast(L("Your friend {} is here!", friend.profile.displayName))
        }
    }

    // MARK: Session entry

    /// Banks the round's score as coins.
    ///
    /// Driven from the end-of-round announcement rather than from the score
    /// itself, so coins are awarded once per round instead of on every point.
    private func bankCoins(completed: Bool) {
        guard let score = session.localPlayer?.score, !hasBankedThisRound else { return }
        hasBankedThisRound = true
        settings.award(score: score, completedRound: completed, game: session.world.name)
        if completed { settings.mission(.finishRound) }
    }

    // MARK: Play time

    /// Counts time played (only while the app is in front), reminds about a
    /// rest, and closes the game a minute after today's time runs out.
    private func countPlay(seconds: Double) {
        guard scenePhase == .active, !session.status.isBusy else { return }
        let game = session.world.name
        if !countedStart {
            countedStart = true
            settings.playtime.startedPlaying(game)
            settings.missionGame(game)
        }
        settings.recordPlay(seconds: seconds, game: game)
        settings.mission(.playMinutes, amount: Int(seconds.rounded()))
        if !countedTogether, !session.isSolo, session.people.count > 1 {
            countedTogether = true
            settings.mission(.playWithOthers)
        }
        switch selfTimer.tick() {
        case .warning:
            showToast(L("One minute left on your timer."))
        case .finished:
            showToast(L("Your timer is up. Time for a break?"))
            if !showMenu, !photoMode { openMenu() }
        case .none:
            break
        }
        sessionSeconds += seconds
        if sessionSeconds >= 20 { takeThumbnailIfMine() }

        if PlayGate.breakDue(settings.parental, sessionSeconds: sessionSeconds, lastReminder: lastRestReminder) {
            lastRestReminder = sessionSeconds
            withAnimation { showingRest = true }
        }
        if let left = closingIn {
            let next = left - Int(seconds)
            if next <= 0 {
                // Friends keep playing: the room goes to one of them.
                if session.canHandOver { session.handOverAndLeave() }
                onExit()
            } else {
                closingIn = next
            }
        } else if settings.playVerdict != .allowed {
            withAnimation { closingIn = 60 }
        }
    }

    @ViewBuilder private var familyNotices: some View {
        VStack(spacing: 10) {
            if let closingIn, let message = PlayGate.message(for: settings.playVerdict) {
                familyBanner(icon: "moon.stars.fill", color: Ablox.Palette.warning,
                             text: message + " " + L("Closing in {} seconds.", closingIn))
            }
            if showingRest {
                familyBanner(icon: "cup.and.saucer.fill", color: Ablox.Palette.accent,
                             text: L("Time for a little rest? Look far away and stretch.")) {
                    withAnimation { showingRest = false }
                }
            }
            Spacer()
        }
        .padding(.top, 70)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func familyBanner(icon: String, color: Color, text: String, dismiss: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let dismiss {
                Button(L("OK"), action: dismiss)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ablox.Palette.accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1.5))
        .frame(maxWidth: 560)
    }

    /// Read out by VoiceOver when it is on; nothing otherwise.
    private func speak(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning, !text.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func enterSession() {
        ProblemRecorder.shared.noteActivity("Playing \"\(session.world.name)\"")
        hasBankedThisRound = false
        session.allowsPlayerChat = settings.parental.chat != .off
        session.allowsWhispers = Whisper.isAllowed(settings.parental.chat)
        switch activeSession.mode {
        case let .solo(world):
            session.startSoloSession(world: world)
        case let .hosting(world, access):
            session.startHosting(world: world, isPublic: access.isPublicOnRouter)
            if access == .internet { cloud.hostRoom(session: session) }
        case let .cloud(room):
            Task { await cloud.join(room, session: session) }
        case let .joining(peer, code):
            session.join(peer, roomCode: code)
        case let .direct(ticket):
            session.join(ticket: ticket)
        }
    }

    // MARK: Controls

    /// A controller's right stick, the arrow keys and the mouse turn the same
    /// camera the touch pad does; its menu button opens the same menu.
    private func startHardware() {
        hardware.sensitivity = Float(settings.cameraSensitivity)
        hardware.invertY = settings.invertCameraY
        hardware.onLook = { yaw, pitch in
            cameraYaw = normalizeDegrees(cameraYaw - yaw)
            let range = pitchRange
            cameraPitch = max(range.lowerBound, min(range.upperBound, cameraPitch + pitch))
        }
        hardware.onMenu = {
            if showMenu { closeMenu() } else if !photoMode { openMenu() }
        }
        hardware.onZoom = { amount in
            let range = PlayPreferences.cameraZoomRange
            settings.preferences.cameraZoom = min(range.upperBound, max(range.lowerBound, settings.preferences.cameraZoom + amount))
        }
        hardware.start()
    }

    private var controlsLayer: some View {
        GeometryReader { proxy in
            let stickOnLeft = !settings.joystickOnRight
            let half = proxy.size.width / 2

            ZStack {
                HStack(spacing: 0) {
                    // The stick owns one half of the screen, the camera the
                    // other. Splitting the whole screen means a thumb never
                    // misses its control.
                    if stickOnLeft {
                        VirtualJoystick(value: $stick) { isRunning = $0 }
                            .frame(width: half)
                        cameraPad
                            .frame(width: half)
                    } else {
                        cameraPad
                            .frame(width: half)
                        VirtualJoystick(value: $stick) { isRunning = $0 }
                            .frame(width: half)
                    }
                }

                VStack {
                    Spacer()
                    if session.scripted.weapon != nil {
                        // Above the jump button, on the same side: the thumb
                        // that is not steering is the one that shoots.
                        HStack {
                            if !stickOnLeft { CombatControls(session: session, isFiring: $isFiring) }
                            Spacer()
                            if stickOnLeft { CombatControls(session: session, isFiring: $isFiring) }
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 14)
                    }
                    // One-handed: the jump button moves over the stick, so one
                    // thumb walks and jumps.
                    let jumpOnLeft = settings.preferences.oneHanded ? stickOnLeft : !stickOnLeft
                    HStack {
                        if jumpOnLeft { jumpButton }
                        Spacer()
                        if !jumpOnLeft { jumpButton }
                    }
                    .padding(.horizontal, settings.preferences.oneHanded ? 150 : 44)
                    .padding(.bottom, settings.preferences.oneHanded ? 150 : 44)
                }
            }
        }
    }

    /// Dragging turns the camera; pinching moves it nearer or further.
    private var cameraPad: some View {
        CameraPad(
            yaw: $cameraYaw,
            pitch: $cameraPitch,
            sensitivity: settings.cameraSensitivity,
            invertY: settings.invertCameraY,
            pitchRange: pitchRange
        )
        .simultaneousGesture(zoomGesture)
    }

    private var zoomGesture: some SwiftUI.Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let start = zoomAtPinchStart ?? settings.preferences.cameraZoom
                if zoomAtPinchStart == nil { zoomAtPinchStart = start }
                let range = PlayPreferences.cameraZoomRange
                settings.preferences.cameraZoom = min(range.upperBound, max(range.lowerBound, start / Float(max(scale, 0.1))))
            }
            .onEnded { _ in zoomAtPinchStart = nil }
    }

    /// Where Settings (or the layout editor) put it, at the size chosen.
    private var jumpButton: some View {
        JumpButton(isPressed: $isJumping)
            .scaleEffect(settings.preferences.buttonScale)
            .offset(x: settings.preferences.jumpButtonOffset.x, y: settings.preferences.jumpButtonOffset.y)
    }

    // MARK: Menu, pictures, watching

    private func openMenu() {
        withAnimation { showMenu = true }
        session.setPaused(true)
    }

    private func closeMenu() {
        withAnimation { showMenu = false }
        session.setPaused(false)
    }

    /// Takes a picture of the world (no buttons), keeps it in the album and
    /// offers to share it.
    private func takePicture() {
        let filter = photoFilter
        let game = session.world.name
        link.snapshot { image in
            guard let image else {
                showToast(L("The picture could not be taken."))
                return
            }
            let finished = filter.apply(to: image)
            if let url = ScreenshotStore.save(finished, game: game) {
                settings.mission(.takePicture)
                showToast(L("Saved to your album"))
                sharing = SharedFile(url: url)
            } else {
                showToast(L("The picture could not be saved."))
            }
        }
    }

    /// A picture of one of the player's own worlds for the Worlds list, once
    /// per visit and a little after arriving (so the world has loaded and
    /// the camera has settled). Not while a menu or photo mode is up.
    private func takeThumbnailIfMine() {
        guard !tookThumbnail, !showMenu, !photoMode else { return }
        let id = session.world.id
        guard store.entries.contains(where: { $0.id == id }) else { return }
        tookThumbnail = true
        link.snapshot { image in
            guard let image,
                  let small = image.preparingThumbnail(of: CGSize(width: 480, height: 480 * image.size.height / max(1, image.size.width))),
                  let png = small.pngData() else { return }
            store.saveThumbnail(png, for: id)
        }
    }

    private func saveClip() {
        clips.saveClip(game: session.world.name) { url in
            if let url {
                showToast(L("Clip saved to your album"))
                sharing = SharedFile(url: url)
            } else {
                showToast(clips.lastError ?? L("The clip could not be saved."))
            }
        }
    }

    private func showToast(_ text: String) {
        speak(text)
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { if toast == text { toast = nil } }
        }
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
                .padding(.bottom, 170)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// Other players, for watching.
    private var watchable: [PlayerSnapshot] {
        session.people.filter { $0.peerID != session.localPeerID && !$0.isHidden }
    }

    /// Knocked out, hidden, or already watching: a bar for watching others.
    @ViewBuilder private var spectateBar: some View {
        let out = session.scripted.isKnockedOut || (session.localPlayer?.isHidden ?? false)
        if (out || spectating != nil), !watchable.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(Ablox.Palette.accent)
                    if let watched = spectating, let person = watchable.first(where: { $0.peerID == watched }) {
                        Button { cycleSpectate(-1) } label: { Image(systemName: "chevron.left") }
                        Text(L("Watching {}", person.profile.displayName))
                            .font(.subheadline.weight(.semibold))
                        Button { cycleSpectate(1) } label: { Image(systemName: "chevron.right") }
                        Button(L("Stop")) { spectating = nil }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Ablox.Palette.accent)
                    } else {
                        Button(L("Watch the others")) { cycleSpectate(1) }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 24)
            }
        }
    }

    private func cycleSpectate(_ step: Int) {
        let people = watchable
        guard !people.isEmpty else { spectating = nil; return }
        let current = people.firstIndex { $0.peerID == spectating } ?? (step > 0 ? -1 : 0)
        let next = ((current + step) % people.count + people.count) % people.count
        spectating = people[next].peerID
    }

    /// Photo mode: the world, a camera to move, filters and a shutter.
    private var photoLayer: some View {
        ZStack {
            photoFilter.previewTint
                .ignoresSafeArea()
                .allowsHitTesting(false)
            cameraPad
            VStack {
                HStack {
                    Button {
                        withAnimation { photoMode = false }
                    } label: {
                        Label(L("Done"), systemImage: "xmark")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(L("Drag to move the camera, pinch to zoom"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(18)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(PhotoFilter.allCases) { filter in
                        Button {
                            photoFilter = filter
                        } label: {
                            Text(filter.displayName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(photoFilter == filter ? Ablox.Palette.accent.opacity(0.45) : Color.black.opacity(0.35), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button(action: takePicture) {
                        Circle()
                            .strokeBorder(.white, lineWidth: 5)
                            .background(Circle().fill(Color.white.opacity(0.35)))
                            .frame(width: 78, height: 78)
                    }
                    .accessibilityLabel(L("Take a picture"))
                }
                .padding(24)
            }
        }
    }

    // MARK: HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            if session.scripted.showsDefaultUI {
                topBar
            } else {
                // A script may hide the top bar, but never the way out.
                HStack {
                    Button(action: onExit) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityLabel(L("Leave world"))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            Spacer()
            if let announcement = session.announcement {
                announcementBanner(announcement.message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.bottom, 30)
            }
            if showChat, session.scripted.showsDefaultUI, settings.parental.chat != .off { chatBar }
            if session.role == .hosting, !session.scriptLog.isEmpty {
                ScriptLogBanner(session: session)
                    .padding(.leading, 18)
                    .padding(.bottom, 130)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.announcement)
        .allowsHitTesting(true)
    }

    private func leaveTapped() {
        if session.canHandOver { choosingHowToLeave = true } else { onExit() }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: leaveTapped) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(L("Leave world"))
            .leaveRoomChoice(isPresented: $choosingHowToLeave, session: session, onLeave: onExit)

            Button {
                openMenu()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(L("Menu"))

            worldChip

            if settings.preferences.showClock {
                PlayClockChip(seconds: sessionSeconds)
            }
            if settings.preferences.showNetworkStatus, session.role == .joined {
                NetworkBadge(ping: session.pingMilliseconds, isReconnecting: session.status.isReconnecting)
            }

            Spacer()

            if session.role == .hosting, !session.roomCode.isEmpty {
                roomCodeChip
            }

            scoreChip

            Button {
                takePicture()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(L("Take a picture"))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showEmotes.toggle() }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(showEmotes ? Ablox.Palette.accent : .white)
            }
            .accessibilityLabel(L("Emotes"))

            Button {
                withAnimation { showScoreboard.toggle() }
            } label: {
                Image(systemName: "list.number")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(showScoreboard ? Ablox.Palette.accent : .white)
            }
            .accessibilityLabel(L("Scoreboard"))

            if settings.parental.chat != .off {
                Button {
                    withAnimation { showChat.toggle() }
                } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(showChat ? Ablox.Palette.accent : .white)
                }
                .accessibilityLabel(L("Chat"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if showScoreboard {
                    PlayerListView(session: session, link: link)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if showEmotes {
                    EmotePanel { gesture in
                        session.send(gesture: gesture)
                        settings.mission(.useEmote)
                        withAnimation { showEmotes = false }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if settings.preferences.showMap, !showScoreboard, !showEmotes {
                    MiniMapView(world: session.world, players: session.roster, localPeerID: session.localPeerID, expanded: false)
                        .frame(width: 150, height: 150)
                        .onTapGesture { withAnimation { mapExpanded = true } }
                }
            }
            .padding(.top, 64)
            .padding(.trailing, 18)
        }
        .overlay {
            if mapExpanded {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .onTapGesture { withAnimation { mapExpanded = false } }
                    MiniMapView(world: session.world, players: session.roster, localPeerID: session.localPeerID, expanded: true)
                        .frame(width: 520, height: 520)
                        .onTapGesture { withAnimation { mapExpanded = false } }
                }
                .transition(.opacity)
            }
        }
    }

    private var worldChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.caption)
                .foregroundStyle(Ablox.Palette.accent)
            Text(session.world.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let ping = session.pingMilliseconds {
                Text(L("{}ms", Int(ping)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ping < 60 ? Ablox.Palette.success : Ablox.Palette.warning)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }

    /// The room code, and whether the room is public. Tapping it lets the
    /// host open or close the room without leaving.
    private var roomCodeChip: some View {
        Menu {
            if settings.parental.allowPublicRooms {
                Button {
                    session.setRoomPublic(true)
                } label: {
                    Label(L("Public — anyone nearby can join"), systemImage: session.isRoomPublic ? "checkmark" : "globe")
                }
            }
            Button {
                session.setRoomPublic(false)
            } label: {
                Label(L("Private — only people with the room code"), systemImage: session.isRoomPublic ? "lock.fill" : "checkmark")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.isRoomPublic ? "globe" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(session.isRoomPublic ? Ablox.Palette.accent : Ablox.Palette.success)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.isRoomPublic ? L("PUBLIC ROOM") : L("PRIVATE ROOM"))
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Ablox.Palette.inkFaint)
                    Text(RoomCode.formatted(session.roomCode))
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
        }
        .accessibilityLabel(L("Room code {}", session.roomCode.map(String.init).joined(separator: " ")))
        .accessibilityValue(session.isRoomPublic ? L("Public") : L("Private"))
    }

    private var scoreChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(Ablox.Palette.warning)
            Text("\(session.localPlayer?.score ?? 0)")
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }

    private var scoreboard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text(L("Players"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ablox.Palette.inkMuted)

                if session.people.isEmpty {
                    Text(L("Just you so far."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }

                ForEach(session.people.sorted { $0.score > $1.score }) { player in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color(player.profile.bodyColor))
                            .frame(width: 10, height: 10)
                        Text(player.profile.displayName)
                            .font(.subheadline.weight(player.peerID == session.localPeerID ? .bold : .regular))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 14)
                        Text("\(player.score)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Ablox.Palette.accent)
                    }
                }
            }
            .frame(width: 220)
        }
    }

    private func announcementBanner(_ message: String) -> some View {
        // Built-in messages ("Checkpoint reached") are catalogue keys and
        // arrive in English from whichever iPad hosts; a script's own text
        // is not in the catalogue and shows as written.
        Text(verbatim: L(message))
            .font(.title3.weight(.bold))
            .padding(.horizontal, 26)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Ablox.Palette.accent.opacity(0.5), lineWidth: 1.5))
            .foregroundStyle(.white)
    }

    private var chatBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.visibleChatLog.suffix(5)) { entry in
                HStack(spacing: 6) {
                    if let partner = entry.privateWith {
                        // A whisper: only the two of them see it.
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Ablox.Palette.magenta)
                        Text(entry.senderID == session.localPeerID ? L("You → {}", partner) : entry.senderName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Ablox.Palette.magenta)
                    } else {
                        Text(entry.senderName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Ablox.Palette.accent)
                    }
                    Text(entry.text)
                        .font(.caption)
                        .foregroundStyle(.white)
                    if entry.wasFiltered {
                        // Marked, so a child can see the filter acting rather
                        // than assume the message arrived that way.
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(Ablox.Palette.warning)
                    }
                }
            }

            // Ready-made phrases: one tap, for small children — and the only
            // way to talk when Settings → Family says phrases only.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickChat.phrases, id: \.self) { phrase in
                        Button {
                            session.sendChat(L(phrase))
                        } label: {
                            Text(L(phrase))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Ablox.Palette.accent.opacity(0.2), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if session.isQuietedByHost {
                Label(L("The host has turned off your chat."), systemImage: "mic.slash.fill")
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            } else if settings.parental.chat == .full {
            HStack(spacing: 9) {
                AbloxTextField(L("Say something…"), text: $chatDraft, limit: AbloxProtocol.maxChatLength, onSubmit: sendChat)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())

                Button(action: sendChat) {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 38, height: 38)
                        .background(Ablox.Palette.brand, in: Circle())
                        .foregroundStyle(.black)
                }
                .disabled(chatDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            }
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.leading, 18)
        .padding(.bottom, 130)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sendChat() {
        session.sendChat(chatDraft)
        chatDraft = ""
    }

    // MARK: Overlays

    /// Deliberately lighter than the disconnect overlay: the world stays
    /// visible behind it, because this is usually over in under a second and
    /// throwing the player back to the lobby for a Wi-Fi blip is worse than
    /// a moment of waiting.
    private func reconnectingOverlay(_ progress: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 11) {
                ProgressView().controlSize(.small).tint(Ablox.Palette.warning)
                Text(progress)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Button(L("Leave"), action: onExit)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ablox.Palette.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Ablox.Palette.warning.opacity(0.5), lineWidth: 1.5))
            .padding(.bottom, 120)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: progress)
    }

    private var connectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 15) {
                ProgressView().controlSize(.large).tint(Ablox.Palette.accent)
                Text(session.isWaitingForHost ? L("Waiting for the host to let you in…")
                     : session.status == .connecting ? L("Connecting…") : L("Looking for the world…"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Button(L("Cancel"), action: onExit)
                    .buttonStyle(NeonButtonStyle(.secondary))
            }
        }
        .transition(.opacity)
    }

    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            GlassCard {
                VStack(spacing: 15) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(Ablox.Palette.warning)
                    Text(L("Disconnected"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Back to menu"), action: onExit)
                        .buttonStyle(NeonButtonStyle(.primary))
                }
                .frame(maxWidth: 340)
            }
            .frame(maxWidth: 400)
        }
    }
}
