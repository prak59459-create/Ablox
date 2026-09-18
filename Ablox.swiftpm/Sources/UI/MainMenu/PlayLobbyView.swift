import SwiftUI

/// Find and join nearby worlds.
struct PlayLobbyView: View {
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    var onEnter: (ActiveSession) -> Void

    @State private var joiningPeer: DiscoveredPeer?
    @State private var roomCodeEntry = ""
    @State private var joinError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                nearbySection
                quickPlaySection
            }
            .padding(Ablox.Metrics.gutter)
        }
        .sheet(item: $joiningPeer) { peer in
            JoinSheet(peer: peer, code: $roomCodeEntry) {
                onEnter(ActiveSession(mode: .joining(peer, code: roomCodeEntry)))
                joiningPeer = nil
            }
            .presentationDetents([.height(340)])
            .presentationBackground(.ultraThinMaterial)
        }
        .alert("Could not join", isPresented: .constant(joinError != nil)) {
            Button("OK") { joinError = nil }
        } message: {
            Text(joinError ?? "")
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Ablox.Palette.magenta.opacity(0.85), Ablox.Palette.accentDeep.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 210)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 130))
                        .foregroundStyle(.white.opacity(0.10))
                        .offset(x: 20, y: -14)
                        .accessibilityHidden(true)
                }

            VStack(alignment: .leading, spacing: 9) {
                Badge("NEARBY MULTIPLAYER", color: Ablox.Palette.accent, systemImage: "antenna.radiowaves.left.and.right")
                Text("Join a friend's world")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Hosts appear here automatically over Bonjour. Type the room code they show you and the connection is encrypted end to end.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            .padding(24)
        }
    }

    // MARK: Nearby

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Nearby worlds", systemImage: "wifi.circle.fill") {
                if session.discoveredPeers.isEmpty && session.browserUnavailableReason == nil {
                    ProgressView().controlSize(.small).tint(Ablox.Palette.accent)
                }
            }

            if let reason = session.browserUnavailableReason {
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Ablox.Palette.warning)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Can't search for iPads")
                                .font(.headline)
                            Text(reason)
                                .font(.subheadline)
                                .foregroundStyle(Ablox.Palette.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            } else if session.discoveredPeers.isEmpty {
                GlassCard {
                    EmptyStateView(
                        title: "Nothing nearby yet",
                        message: "Ask a friend to open a world and tap Host. Both iPads need to be on the same Wi-Fi, or close enough for a direct connection.",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
            } else {
                VStack(spacing: 11) {
                    ForEach(session.discoveredPeers) { peer in
                        peerRow(peer)
                    }
                }
            }
        }
    }

    private func peerRow(_ peer: DiscoveredPeer) -> some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(peer.isStudioSession ? Ablox.Palette.warning.opacity(0.2) : Ablox.Palette.accent.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: peer.isStudioSession ? "hammer.fill" : "globe.americas.fill")
                        .foregroundStyle(peer.isStudioSession ? Ablox.Palette.warning : Ablox.Palette.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(peer.worldName)
                            .font(.headline)
                            .foregroundStyle(Ablox.Palette.ink)
                        Image(systemName: "lock.shield.fill")
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.success)
                            .accessibilityLabel("Encrypted")
                    }
                    Text("\(peer.hostName) · \(peer.subtitle)")
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }

                Spacer()

                if !peer.isCompatible {
                    Badge("Update needed", color: Ablox.Palette.warning)
                } else if peer.isFull {
                    Badge("Full", color: Ablox.Palette.inkFaint)
                } else {
                    Button("Join") {
                        roomCodeEntry = ""
                        joiningPeer = peer
                    }
                    .buttonStyle(NeonButtonStyle(.primary))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Quick play

    private var quickPlaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Play on your own", systemImage: "play.circle.fill")

            if store.entries.isEmpty {
                GlassCard {
                    EmptyStateView(
                        title: "No worlds yet",
                        message: "Head to Worlds to make one. You can play it solo, or host it for friends.",
                        systemImage: "square.stack.3d.up"
                    )
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 13)], spacing: 13) {
                    ForEach(store.entries.prefix(6)) { entry in
                        Button {
                            guard let world = store.load(entry) else { return }
                            onEnter(ActiveSession(mode: .solo(world)))
                        } label: {
                            GlassCard(padding: 15) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Image(systemName: "cube.transparent.fill")
                                        .font(.title2)
                                        .foregroundStyle(Ablox.Palette.accent)
                                    Text(entry.name)
                                        .font(.headline)
                                        .foregroundStyle(Ablox.Palette.ink)
                                        .lineLimit(1)
                                    Text(entry.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Ablox.Palette.inkMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Join sheet

private struct JoinSheet: View {
    let peer: DiscoveredPeer
    @Binding var code: String
    var onJoin: () -> Void

    @FocusState private var codeFocused: Bool

    private var isValid: Bool { RoomCode.isPlausible(code) }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(peer.worldName)
                    .font(.title2.weight(.bold))
                Text("Hosted by \(peer.hostName)")
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            .padding(.top, 26)

            VStack(spacing: 8) {
                Text("Room code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ablox.Palette.inkMuted)

                TextField("ABC DEF", text: $code)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 260)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isValid ? Ablox.Palette.success.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1.5)
                    )
                    .onSubmit { if isValid { onJoin() } }

                Text("The host's iPad shows this code.")
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }

            Button("Join world", action: onJoin)
                .buttonStyle(NeonButtonStyle(.primary, fullWidth: true))
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.5)
                .padding(.horizontal, 30)

            Spacer(minLength: 0)
        }
        .onAppear { codeFocused = true }
    }
}
