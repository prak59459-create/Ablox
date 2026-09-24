import SwiftUI

/// The full-screen play surface: 3D viewport underneath, HUD on top.
public struct PlayScreen: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
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

    public init(session: SessionCoordinator, activeSession: ActiveSession, onExit: @escaping () -> Void) {
        self.session = session
        self.activeSession = activeSession
        self.onExit = onExit
    }

    /// First person may look well up and down; the orbit camera may not go
    /// under the floor.
    private var pitchRange: ClosedRange<Float> {
        session.scripted.camera.mode == .firstPerson ? -80...80 : -75...20
    }

    private var movementInput: MovementInput {
        MovementInput(stick: stick, isJumping: isJumping, isRunning: isRunning, cameraYawDegrees: cameraYaw)
    }

    public var body: some View {
        ZStack {
            GameViewport(
                session: session,
                input: .constant(movementInput),
                cameraYaw: $cameraYaw,
                cameraPitch: $cameraPitch,
                soundEnabled: settings.soundEnabled,
                hapticsEnabled: settings.hapticsEnabled,
                isFiring: isFiring && session.scripted.weapon != nil,
                graphicsQuality: settings.graphicsQuality,
                showFrameRate: settings.showFrameRate
            )
            .ignoresSafeArea()

            // A script can hide the joystick and buttons — a title screen,
            // a cutscene — and the top bar and chat.
            if session.scripted.showsControls {
                controlsLayer
            }
            ScriptHUDLayer(session: session)
            hudLayer

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
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: enterSession)
        .onChange(of: session.announcement) { _, announcement in
            // The end-of-round banner is the one signal that the round is
            // over for everyone, host or client.
            guard let message = announcement?.message else { return }
            if message.contains("goal") || message.localizedCaseInsensitiveContains("win") {
                bankCoins(completed: true)
            }
        }
        .onDisappear { bankCoins(completed: false) }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding is what kills the TCP connection, so returning is
            // the single most likely moment a session needs recovering. Bring
            // any pending attempt forward rather than waiting out a backoff
            // scheduled while the iPad was asleep.
            if phase == .active { session.applicationDidBecomeActive() }
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
        settings.award(score: score, completedRound: completed)
    }

    private func enterSession() {
        hasBankedThisRound = false
        switch activeSession.mode {
        case let .solo(world):
            session.startSoloSession(world: world)
        case let .hosting(world, isPublic):
            session.startHosting(world: world, isPublic: isPublic)
        case let .joining(peer, code):
            session.join(peer, roomCode: code)
        }
    }

    // MARK: Controls

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
                        CameraPad(
                            yaw: $cameraYaw,
                            pitch: $cameraPitch,
                            sensitivity: settings.cameraSensitivity,
                            invertY: settings.invertCameraY,
                            pitchRange: pitchRange
                        )
                        .frame(width: half)
                    } else {
                        CameraPad(
                            yaw: $cameraYaw,
                            pitch: $cameraPitch,
                            sensitivity: settings.cameraSensitivity,
                            invertY: settings.invertCameraY,
                            pitchRange: pitchRange
                        )
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
                    HStack {
                        if !stickOnLeft { JumpButton(isPressed: $isJumping) }
                        Spacer()
                        if stickOnLeft { JumpButton(isPressed: $isJumping) }
                    }
                    .padding(.horizontal, 44)
                    .padding(.bottom, 44)
                }
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
            if showChat, session.scripted.showsDefaultUI { chatBar }
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

    private var topBar: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(L("Leave world"))

            worldChip

            Spacer()

            if session.role == .hosting, !session.roomCode.isEmpty {
                roomCodeChip
            }

            scoreChip

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
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .overlay(alignment: .topTrailing) {
            if showScoreboard {
                PlayerListView(session: session)
                    .padding(.top, 64)
                    .padding(.trailing, 18)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
            Button {
                session.setRoomPublic(true)
            } label: {
                Label(L("Public — anyone nearby can join"), systemImage: session.isRoomPublic ? "checkmark" : "globe")
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
                    Text(entry.senderName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Ablox.Palette.accent)
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

            HStack(spacing: 9) {
                TextField(L("Say something…"), text: $chatDraft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .onSubmit(sendChat)

                Button(action: sendChat) {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 38, height: 38)
                        .background(Ablox.Palette.brand, in: Circle())
                        .foregroundStyle(.black)
                }
                .disabled(chatDraft.trimmingCharacters(in: .whitespaces).isEmpty)
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
                Text(session.status == .connecting ? L("Connecting…") : L("Looking for the world…"))
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
