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
    /// Which favourite emote the controller's Y plays next.
    @State private var nextFavourite = 0
    /// A game controller, keyboard or mouse, beside the touch controls.
    @StateObject private var hardware = HardwareInput()

    // Play screen options (see HUDExtras.swift).
    @State private var tracker = PlayTracker()
    @State private var buttonsHidden = false
    @State private var keepWalking = false
    @State private var holdingRun = false
    @State private var showShortcuts = false
    @State private var unreadChat = 0
    /// A line naming this player came while the chat was closed.
    @State private var mentioned = false
    // Photo mode (see PhotoExtras.swift).
    @State private var countdown: Int?
    @State private var flashing = false
    @State private var lastShot: URL?
    @State private var shooting = false

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
        var move = stick == .zero ? hardware.stick : stick
        if keepWalking { move = TouchStick.keepWalking(move) }
        let running = isRunning || hardware.running || holdingRun || (settings.preferences.hud.alwaysRun && move != .zero)
        return MovementInput(stick: move,
                             isJumping: isJumping || hardware.jumping,
                             isRunning: running,
                             cameraYawDegrees: cameraYaw)
    }

    // In pieces, each type-checked on its own: as one expression the play
    // screen was among the slowest things in the app to compile.
    public var body: some View {
        reactions(lifecycle(screen))
    }

    /// Photo mode's zoom lens is the field of view, for photo mode only.
    private var viewportPreferences: PlayPreferences {
        let zoom = settings.memory.photo.zoom
        guard photoMode, zoom != 0 else { return settings.preferences }
        var preferences = settings.preferences
        preferences.fieldOfViewBoost += zoom
        return preferences
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
            preferences: viewportPreferences,
            spectating: spectating,
            preferFirstPerson: preferFirstPerson,
            photoMode: photoMode,
            link: link,
            friends: friendIDs
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
        if !session.isSolo, !buttonsHidden {
            RoomHUD(session: session)
                .padding(.top, settings.preferences.hud.showCompass ? 106 : 68)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        spectateBar
        if showShortcuts {
            ShortcutsCard { withAnimation { showShortcuts = false } }
        }
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
            onLeave: onExit,
            tracker: tracker,
            onCameraBehind: { closeMenu(); cameraBehind() },
            onHideButtons: { closeMenu(); withAnimation { buttonsHidden = true } },
            onShortcuts: { closeMenu(); withAnimation { showShortcuts = true } }
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
            .onChange(of: showChat) { _, open in
                hardware.suspended = open || showMenu
                if open {
                    unreadChat = 0
                    mentioned = false
                }
            }
            .onChange(of: session.visibleChatLog.last?.id) { _, newest in
                if newest != nil { noticeNewLine() }
            }
            .onChange(of: settings.preferences.chat) { _, chat in session.chatOptions = chat }
            // Any touch at all means someone is there.
            .background(TouchWatcher { tracker.idle.touched(at: Date().timeIntervalSinceReferenceDate) })
            .onChange(of: showMenu) { _, open in hardware.suspended = open || showChat }
            .sheet(item: $sharing) { file in
                ActivityShareSheet(items: [file.url])
            }
            .onChange(of: session.roster) { _, roster in
                // Whoever was being watched has gone.
                if let watched = spectating, !roster.contains(where: { $0.peerID == watched }) { spectating = nil }
                noticeWhoIsHere()
                if let me = session.localPlayer {
                    tracker.tally.record(position: me.position, grounded: me.isGrounded, time: Date().timeIntervalSinceReferenceDate)
                }
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
                    // The pose chosen for winning, if there is one.
                    if let victory = settings.memory.emotes.victory { session.send(gesture: .emote(victory)) }
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

    // MARK: New lines

    /// Someone said something: read aloud or felt if the player asked,
    /// and counted on the chat button while it is closed.
    private func noticeNewLine() {
        guard let entry = session.visibleChatLog.last, entry.senderID != session.localPeerID else { return }
        let chat = settings.preferences.chat
        if chat.readAloud, settings.soundEnabled {
            LineReader.shared.speak(entry.senderName + ": " + entry.text, volume: Float(settings.preferences.effectsVolume))
        }
        if chat.feelNewMessages, settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        guard !showChat else { return }
        unreadChat += 1
        if chat.highlightMentions, ChatTidy.mentions(settings.profile.displayName, in: entry.text) { mentioned = true }
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
            // The first time today with a friend earns a little extra.
            if let coins = settings.friendBonus() {
                showToast(L("Your friend {} is here! +{} coins", friend.profile.displayName, coins))
            } else {
                showToast(L("Your friend {} is here!", friend.profile.displayName))
            }
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
        if completed {
            settings.memory.counters.roundsWon += 1
            advance(settings.mission(.finishRound))
        }
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
            advance(settings.missionGame(game))
            if let coins = settings.firstVisitBonus(game) { showToast(L("First visit here: +{} coins", coins)) }
            settings.joinEvent()
            tracker.weeklyDone = settings.memory.weekly.done(on: settings.thisWeek)
            tracker.eventWaiting = settings.eventMissionWaiting
        }
        settings.recordPlay(seconds: seconds, game: game)
        advance(settings.mission(.playMinutes, amount: Int(seconds.rounded())))
        if !countedTogether, !session.isSolo, session.people.count > 1 {
            countedTogether = true
            advance(settings.mission(.playWithOthers))
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
        checkAway()
        checkPower()
        checkBigMissions()

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

    /// A game played alone pauses itself when nobody has touched anything
    /// for a while (Play screen options).
    private func checkAway() {
        let now = Date().timeIntervalSinceReferenceDate
        if hardware.stick != .zero || hardware.jumping || keepWalking || showMenu || !session.isSolo {
            tracker.idle.touched(at: now)
        }
        guard settings.preferences.hud.pauseWhenAway, session.isSolo, !photoMode, tracker.idle.isAway(at: now) else { return }
        tracker.idle.touched(at: now)
        openMenu()
        showToast(L("Paused while you were away."))
    }

    /// Says so when this week's missions or the season's one are done.
    private func checkBigMissions() {
        let week = settings.thisWeek
        let done = settings.memory.weekly.done(on: week)
        if let finished = settings.memory.weekly.missions(on: week).first(where: { done.contains($0.id) && !tracker.weeklyDone.contains($0.id) }) {
            showToast(L("Weekly mission done: {}! Take the coins on the Play tab.", finished.title))
        }
        tracker.weeklyDone = done
        let waiting = settings.eventMissionWaiting
        if waiting, !tracker.eventWaiting, let event = settings.currentEvent {
            showToast(L("{} mission done! Take the coins on the Play tab.", event.displayName))
        }
        tracker.eventWaiting = waiting
    }

    /// Once each per visit: a low battery, a hot iPad.
    private func checkPower() {
        guard settings.preferences.hud.powerWarnings else { return }
        let battery = BatteryReading.now()
        if let notice = PowerNotice.message(batteryLevel: battery.map { Double($0.percent) / 100 }, charging: battery?.charging ?? false,
                                            heat: DeviceHeat.now, alreadySaid: tracker.powerSaid) {
            tracker.powerSaid.insert(notice.key)
            showToast(notice.text)
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
        .padding(.top, settings.preferences.hud.showCompass ? 108 : 70)
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
        session.chatOptions = settings.preferences.chat
        session.allowsWhispers = Whisper.isAllowed(settings.parental.chat)
        switch activeSession.mode {
        case let .solo(world):
            session.startSoloSession(world: world)
        case let .hosting(world, access):
            session.startHosting(world: world, isPublic: access.isPublicOnRouter)
            if access == .internet { cloud.hostRoom(session: session) }
            if let coins = settings.hostBonus() { showToast(L("Hosting a room: +{} coins", coins)) }
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
        hardware.onEmote = { slot in playFavourite(slot) }
        hardware.onZoom = { amount in zoom(by: amount) }
        hardware.onAction = { action in handle(action) }
        hardware.start()
    }

    /// A key or button that does one thing (see `PlayShortcuts`).
    private func handle(_ action: PlayKeyAction) {
        switch action {
        case .chat:
            if settings.parental.chat != .off { withAnimation { showChat = true } }
        case .map:
            withAnimation { mapExpanded.toggle() }
        case .picture:
            takePicture()
        case .view:
            if session.scripted.camera.mode == .thirdPerson { preferFirstPerson.toggle() }
        case .cameraBehind:
            cameraBehind()
        case .hideButtons:
            withAnimation { buttonsHidden.toggle() }
        case .shortcuts:
            withAnimation { showShortcuts.toggle() }
        case .watchNext:
            if spectating != nil { cycleSpectate(1) }
        case .watchPrevious:
            if spectating != nil { cycleSpectate(-1) }
        }
    }

    private func zoom(by amount: Float) {
        let range = PlayPreferences.cameraZoomRange
        settings.preferences.cameraZoom = min(range.upperBound, max(range.lowerBound, settings.preferences.cameraZoom + amount))
    }

    /// The camera straight behind the player, level again.
    private func cameraBehind() {
        guard let me = session.localPlayer else { return }
        cameraYaw = CameraHabits.behind(bodyYaw: me.yawDegrees)
        cameraPitch = -14
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
                        VirtualJoystick(value: $stick, options: settings.preferences.hud, fixedOnLeft: true) { isRunning = $0 }
                            .frame(width: half)
                        cameraPad
                            .frame(width: half)
                    } else {
                        cameraPad
                            .frame(width: half)
                        VirtualJoystick(value: $stick, options: settings.preferences.hud, fixedOnLeft: false) { isRunning = $0 }
                            .frame(width: half)
                    }
                }

                if !buttonsHidden {
                    buttons(stickOnLeft: stickOnLeft)
                }
            }
        }
    }

    /// The jump button and friends, on the thumb's side.
    private func buttons(stickOnLeft: Bool) -> some View {
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
                    HStack(alignment: .bottom) {
                        if jumpOnLeft { jumpCluster(onLeft: true) }
                        Spacer()
                        if !jumpOnLeft { jumpCluster(onLeft: false) }
                    }
                    .padding(.horizontal, settings.preferences.oneHanded ? 150 : 44)
                    .padding(.bottom, settings.preferences.oneHanded ? 150 : 44)
                }
                .opacity(settings.preferences.hud.opacity)
    }

    /// The jump button, with the extra buttons chosen in the options on its
    /// inner side.
    private func jumpCluster(onLeft: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            if !onLeft { extraButtons }
            jumpButton
            if onLeft { extraButtons }
        }
    }

    @ViewBuilder private var extraButtons: some View {
        let hud = settings.preferences.hud
        if hud.showZoomButtons || hud.showWalkButton || hud.showRunButton {
            VStack(spacing: 12) {
                if hud.showZoomButtons {
                    ZoomButtons { zoom(by: $0) }
                }
                if hud.showWalkButton {
                    HUDRoundButton(systemImage: keepWalking ? "figure.walk.motion" : "figure.walk", label: L("Keep walking"),
                                   active: keepWalking) { keepWalking.toggle() }
                }
                if hud.showRunButton {
                    RunButton(isPressed: $holdingRun, haptics: hud.buttonHaptics)
                }
            }
        }
    }

    /// Dragging turns the camera; pinching moves it nearer or further.
    private var cameraPad: some View {
        let behind: (() -> Void)? = settings.preferences.hud.doubleTapResetsCamera && !photoMode ? { cameraBehind() } : nil
        return CameraPad(
            yaw: $cameraYaw,
            pitch: $cameraPitch,
            sensitivity: settings.cameraSensitivity,
            invertY: settings.invertCameraY,
            pitchRange: pitchRange,
            invertX: settings.preferences.hud.invertLookX,
            verticalSpeed: settings.preferences.hud.verticalLookSpeed,
            onDoubleTap: behind
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
        JumpButton(isPressed: $isJumping, haptics: settings.preferences.hud.buttonHaptics)
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
        takePicture(inPhotoMode: false)
    }

    /// In photo mode the picture is also cut, framed and stamped as chosen,
    /// and kept in the corner rather than shared straight away.
    private func takePicture(inPhotoMode: Bool) {
        let filter = photoFilter
        let game = session.world.name
        let options = settings.memory.photo
        link.snapshot { image in
            guard let image else {
                showToast(L("The picture could not be taken."))
                return
            }
            let filtered = filter.apply(to: image)
            let finished = inPhotoMode ? PhotoComposer.compose(filtered, options: options, game: game) : filtered
            if let url = ScreenshotStore.save(finished, game: game) {
                advance(settings.mission(.takePicture))
                if inPhotoMode {
                    lastShot = url
                } else {
                    showToast(L("Saved to your album"))
                    sharing = SharedFile(url: url)
                }
            } else {
                showToast(L("The picture could not be saved."))
            }
        }
    }

    /// The shutter: the timer first if there is one, then one picture or a
    /// burst of three, each with a flash.
    private func shoot() {
        guard !shooting else { return }
        shooting = true
        let options = settings.memory.photo
        Task { @MainActor in
            defer { shooting = false }
            if options.timer > 0 {
                for left in stride(from: options.timer, to: 0, by: -1) {
                    countdown = left
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard photoMode else { countdown = nil; return }
                }
                countdown = nil
            }
            for shot in 0..<options.shots {
                takePicture(inPhotoMode: true)
                withAnimation(.easeOut(duration: 0.05)) { flashing = true }
                if settings.hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.easeIn(duration: 0.25)) { flashing = false }
                if shot < options.shots - 1 { try? await Task.sleep(nanoseconds: 400_000_000) }
            }
            if options.shots > 1 { showToast(L("{} pictures saved to your album", options.shots)) } else { showToast(L("Saved to your album")) }
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
                settings.memory.counters.clipsSaved += 1
                showToast(L("Clip saved to your album"))
                sharing = SharedFile(url: url)
            } else {
                showToast(clips.lastError ?? L("The clip could not be saved."))
            }
        }
    }

    /// A favourite emote from a key (its slot) or the controller (-1: the
    /// next one in turn).
    private func playFavourite(_ slot: Int) {
        let favourites = settings.memory.emotes.emotes
        guard !favourites.isEmpty else { return }
        let emote: Emote
        if slot >= 0 {
            guard let chosen = settings.memory.emotes.emote(inSlot: slot) else { return }
            emote = chosen
        } else {
            emote = favourites[nextFavourite % favourites.count]
            nextFavourite += 1
        }
        session.send(gesture: .emote(emote))
        settings.noteGesture(.emote(emote))
        advance(settings.mission(.useEmote))
    }

    /// Says so when something done here finished one of today's missions.
    private func advance(_ finished: [Mission]) {
        guard let mission = finished.first else { return }
        showToast(L("Mission done: {}! Take the coins on the Play tab.", mission.title))
    }

    private func showToast(_ text: String) {
        tracker.note(text)
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
            if settings.memory.photo.grid || settings.memory.photo.crop != .original {
                ThirdsGrid(crop: settings.memory.photo.crop)
            }
            if flashing {
                Color.white.opacity(0.85).ignoresSafeArea().allowsHitTesting(false)
            }
            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .allowsHitTesting(false)
            }
            photoControls
        }
    }

    private var photoControls: some View {
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
                PhotoOptionsBar(options: $settings.memory.photo)
            }
            .padding(18)
            Spacer()
            PhotoPoseBar(zoom: $settings.memory.photo.zoom, poses: Array(settings.memory.emotes.ordered.prefix(10))) { pose in
                session.send(gesture: .emote(pose))
            }
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
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
                    }
                }
                LastShotButton(url: lastShot) {
                    if let lastShot { sharing = SharedFile(url: lastShot) }
                }
                Button(action: shoot) {
                    Circle()
                        .strokeBorder(.white, lineWidth: 5)
                        .background(Circle().fill(Color.white.opacity(shooting ? 0.7 : 0.35)))
                        .frame(width: 78, height: 78)
                }
                .accessibilityLabel(L("Take a picture"))
            }
            .padding(24)
        }
    }

    // MARK: HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            if buttonsHidden {
                // Everything put away, for a clean picture or video; this
                // one small button brings it back.
                HStack {
                    HUDRoundButton(systemImage: "eye", label: L("Show the buttons"), size: 34) {
                        withAnimation { buttonsHidden = false }
                    }
                    .opacity(0.7)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            } else if session.scripted.showsDefaultUI {
                topBar
                if settings.preferences.hud.showCompass {
                    CompassStrip(bearing: Compass.bearing(cameraYaw: cameraYaw))
                        .padding(.top, 8)
                        .opacity(settings.preferences.hud.opacity)
                }
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
            if showChat, session.scripted.showsDefaultUI, settings.parental.chat != .off {
                ChatPanel(session: session, tracker: tracker)
            }
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

    private var hud: HUDOptions { settings.preferences.hud }

    /// This player's place by score, with others in the room.
    private var myPlace: Int? {
        guard !session.isSolo, let me = session.localPlayer else { return nil }
        return Placing.place(of: me.score, among: session.people.map(\.score))
    }

    private var friendIDs: Set<PeerID> {
        Set(session.people.map(\.peerID).filter { settings.social.isFriend($0) })
    }

    private func barButton(_ systemImage: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(active ? Ablox.Palette.accent : .white)
        }
        .accessibilityLabel(label)
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

            if hud.shows(.worldName) {
                worldChip
            }

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

            if hud.shows(.score) {
                scoreChip
            }
            if hud.showRank, let place = myPlace {
                PlaceChip(place: place, count: session.people.count)
            }

            if hud.showViewButton, session.scripted.camera.mode == .thirdPerson {
                barButton(preferFirstPerson ? "person.fill.viewfinder" : "eye.fill", L("First or third person"), active: preferFirstPerson) {
                    preferFirstPerson.toggle()
                }
            }

            if hud.shows(.camera) {
                barButton("camera.fill", L("Take a picture")) { takePicture() }
            }

            if hud.shows(.emotes) {
                barButton("face.smiling", L("Emotes"), active: showEmotes) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showEmotes.toggle() }
                }
            }

            if hud.shows(.scoreboard) {
                barButton("list.number", L("Scoreboard"), active: showScoreboard) {
                    withAnimation { showScoreboard.toggle() }
                }
            }

            if settings.parental.chat != .off {
                barButton("bubble.left.fill", L("Chat"), active: showChat) {
                    withAnimation { showChat.toggle() }
                }
                .overlay(alignment: .topTrailing) {
                    if unreadChat > 0 {
                        Text(unreadChat > 9 ? "9+" : "\(unreadChat)")
                            .font(.system(size: 10, weight: .black).monospacedDigit())
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(mentioned ? Ablox.Palette.warning : Ablox.Palette.danger, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 4, y: -4)
                            .accessibilityLabel(L("{} new messages", unreadChat))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .opacity(hud.opacity)
        .overlay(alignment: .topLeading) {
            FactChips(session: session)
                .padding(.top, 66)
                .padding(.leading, 18)
                .opacity(hud.opacity)
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if showScoreboard {
                    PlayerListView(session: session, link: link)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if showEmotes {
                    EmotePanel { gesture in
                        session.send(gesture: gesture)
                        settings.noteGesture(gesture)
                        advance(settings.mission(.useEmote))
                        withAnimation { showEmotes = false }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if settings.preferences.showMap, !showScoreboard, !showEmotes {
                    MiniMapView(world: session.world, players: session.roster, localPeerID: session.localPeerID, expanded: false,
                                metresAcross: hud.mapSize.metresAcross,
                                heading: hud.mapTurnsWithCamera ? Compass.bearing(cameraYaw: cameraYaw) : nil,
                                friends: friendIDs)
                        .frame(width: hud.mapSize.points, height: hud.mapSize.points)
                        .opacity(max(0.6, hud.opacity))
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
                    MiniMapView(world: session.world, players: session.roster, localPeerID: session.localPeerID, expanded: true,
                                friends: friendIDs)
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
