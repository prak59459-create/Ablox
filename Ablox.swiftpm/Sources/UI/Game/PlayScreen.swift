import SwiftUI

/// The full-screen play surface: 3D viewport underneath, HUD on top.
public struct PlayScreen: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

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

    public init(session: SessionCoordinator, activeSession: ActiveSession, onExit: @escaping () -> Void) {
        self.session = session
        self.activeSession = activeSession
        self.onExit = onExit
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
                cameraPitch: $cameraPitch
            )
            .ignoresSafeArea()

            controlsLayer
            hudLayer

            if session.status.isBusy {
                connectingOverlay
            }
            if case let .error(message) = session.status {
                errorOverlay(message)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: enterSession)
    }

    // MARK: Session entry

    private func enterSession() {
        switch activeSession.mode {
        case let .solo(world):
            session.startSoloSession(world: world)
        case let .hosting(world):
            session.startHosting(world: world)
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
                            invertY: settings.invertCameraY
                        )
                        .frame(width: half)
                    } else {
                        CameraPad(
                            yaw: $cameraYaw,
                            pitch: $cameraPitch,
                            sensitivity: settings.cameraSensitivity,
                            invertY: settings.invertCameraY
                        )
                        .frame(width: half)
                        VirtualJoystick(value: $stick) { isRunning = $0 }
                            .frame(width: half)
                    }
                }

                VStack {
                    Spacer()
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
            topBar
            Spacer()
            if let announcement = session.announcement {
                announcementBanner(announcement.message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.bottom, 30)
            }
            if showChat { chatBar }
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
            .accessibilityLabel("Leave world")

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
            .accessibilityLabel("Scoreboard")

            Button {
                withAnimation { showChat.toggle() }
            } label: {
                Image(systemName: "bubble.left.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(showChat ? Ablox.Palette.accent : .white)
            }
            .accessibilityLabel("Chat")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .overlay(alignment: .topTrailing) {
            if showScoreboard {
                scoreboard
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
                Text("\(Int(ping))ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ping < 60 ? Ablox.Palette.success : Ablox.Palette.warning)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }

    private var roomCodeChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(Ablox.Palette.success)
            VStack(alignment: .leading, spacing: 0) {
                Text("ROOM CODE")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Ablox.Palette.inkFaint)
                Text(RoomCode.formatted(session.roomCode))
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
        .accessibilityLabel("Room code \(session.roomCode.map(String.init).joined(separator: " "))")
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
                Text("Players")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ablox.Palette.inkMuted)

                if session.roster.isEmpty {
                    Text("Just you so far.")
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }

                ForEach(session.roster.sorted { $0.score > $1.score }) { player in
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
        Text(message)
            .font(.title3.weight(.bold))
            .padding(.horizontal, 26)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Ablox.Palette.accent.opacity(0.5), lineWidth: 1.5))
            .foregroundStyle(.white)
    }

    private var chatBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.chatLog.suffix(5)) { entry in
                HStack(spacing: 6) {
                    Text(entry.senderName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Ablox.Palette.accent)
                    Text(entry.text)
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 9) {
                TextField("Say something…", text: $chatDraft)
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

    private var connectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 15) {
                ProgressView().controlSize(.large).tint(Ablox.Palette.accent)
                Text(session.status == .connecting ? "Connecting…" : "Looking for the world…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Button("Cancel", action: onExit)
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
                    Text("Disconnected")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Back to menu", action: onExit)
                        .buttonStyle(NeonButtonStyle(.primary))
                }
                .frame(maxWidth: 340)
            }
            .frame(maxWidth: 400)
        }
    }
}
