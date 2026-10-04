import SwiftUI

/// Who is in the session: name, score, role and latency, with a mute control.
///
/// Muting lives here rather than only on a chat message because the moment
/// you want it is usually *after* the message has scrolled away.
struct PlayerListView: View {
    @ObservedObject var session: SessionCoordinator
    /// For the picture a report keeps.
    var link: ViewportLink?
    @EnvironmentObject private var settings: AppSettings

    @State private var whispering: PlayerSnapshot?
    @State private var reporting: PlayerSnapshot?
    @State private var removing: PlayerSnapshot?

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label(L("Players"), icon: .friends)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                    Spacer()
                    if let ping = session.pingMilliseconds {
                        pingBadge(ping)
                    }
                }

                if session.people.isEmpty {
                    Text(L("Just you so far."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }

                ForEach(session.people.sorted { $0.score > $1.score }) { player in
                    row(player)
                }

                if settings.muteList.count > 0 {
                    Divider().background(Color.white.opacity(0.08))
                    Button {
                        settings.muteList.removeAll()
                        session.muteList = settings.muteList
                    } label: {
                        Label(L("Unmute everyone ({})", settings.muteList.count), systemImage: "speaker.wave.2.fill")
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 250)
        }
        .sheet(item: $whispering) { player in
            WhisperSheet(session: session, player: player)
        }
        .sheet(item: $reporting) { player in
            ReportSheet(session: session, player: player, link: link)
                .environmentObject(settings)
        }
        .alert(L("Take {} out of the room?", removing?.profile.displayName ?? ""),
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(L("Cancel"), role: .cancel) { removing = nil }
            Button(L("Remove"), role: .destructive) {
                if let removing { session.removeFromRoom(removing.peerID) }
                removing = nil
            }
        } message: {
            Text(L("They can't come back into this room until you start a new one."))
        }
    }

    private func row(_ player: PlayerSnapshot) -> some View {
        let isSelf = player.peerID == session.localPeerID
        let isHost = session.role == .hosting && isSelf
        let isMuted = settings.muteList.isMuted(player.peerID)

        return HStack(spacing: 9) {
            Circle()
                .fill(Color(player.profile.bodyColor))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle().strokeBorder(teamColour(player.team), lineWidth: player.team.isEmpty ? 0 : 2)
                        .frame(width: 15, height: 15)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(player.profile.displayName)
                    .font(.subheadline.weight(isSelf ? .bold : .regular))
                    .foregroundStyle(isMuted ? Ablox.Palette.inkFaint : Ablox.Palette.ink)
                    .lineLimit(1)
                    .strikethrough(isMuted, color: Ablox.Palette.inkFaint)
                HStack(spacing: 5) {
                    if isHost {
                        Text(L("Host"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Ablox.Palette.success)
                    }
                    if settings.social.isFriend(player.peerID) {
                        Text(L("Friend"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Ablox.Palette.accent)
                    }
                    if session.roomState.ready.contains(player.peerID) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Ablox.Palette.success)
                            .accessibilityLabel(L("Ready"))
                    }
                    if session.roomState.quieted.contains(player.peerID) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Ablox.Palette.warning)
                    }
                }
            }

            Spacer(minLength: 8)

            Text("\(player.score)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Ablox.Palette.accent)

            // You cannot mute yourself — see MuteList.allows(_:localPeerID:).
            if !isSelf {
                actions(for: player, isMuted: isMuted)
            }
        }
    }

    private func teamColour(_ team: String) -> Color {
        TeamPicker.colorHex(for: team).flatMap { ColorRGBA(hex: $0) }.map { Color($0) } ?? Ablox.Palette.accent
    }

    /// Everything to do about one other player.
    private func actions(for player: PlayerSnapshot, isMuted: Bool) -> some View {
        let id = player.peerID
        let name = player.profile.displayName
        let isFriend = settings.social.isFriend(id)
        let isHosting = session.role == .hosting
        let quieted = session.roomState.quieted.contains(id)
        return Menu {
            Button {
                if isFriend { settings.social.removeFriend(id) } else { settings.social.addFriend(id, name: name) }
            } label: {
                Label(isFriend ? L("Remove friend") : L("Add friend"), systemImage: isFriend ? "person.badge.minus" : "person.badge.plus")
            }
            if isHosting || session.roomState.allowsWarp {
                Button {
                    session.warp(to: id)
                } label: {
                    Label(L("Go to them"), systemImage: "figure.walk.arrival")
                }
            }
            if session.allowsWhispers, session.allowsPlayerChat, !session.isQuietedByHost {
                Button {
                    whispering = player
                } label: {
                    Label(L("Whisper"), systemImage: "bubble.left.and.text.bubble.right")
                }
            }
            Button {
                settings.muteList.toggle(id)
                session.muteList = settings.muteList
            } label: {
                Label(isMuted ? L("Unmute") : L("Mute"), systemImage: isMuted ? "speaker.wave.2" : "speaker.slash")
            }
            if isHosting {
                Divider()
                Menu {
                    Button(L("No team")) { session.assignTeams([id: ""]) }
                    ForEach(TeamPicker.names, id: \.self) { team in
                        Button(L(team)) { session.assignTeams([id: team]) }
                    }
                } label: {
                    Label(L("Team"), systemImage: "person.3")
                }
                Button {
                    session.setQuieted(id, !quieted)
                } label: {
                    Label(quieted ? L("Let them chat again") : L("Turn off their chat for everyone"), systemImage: "mic.slash")
                }
                Button(role: .destructive) {
                    removing = player
                } label: {
                    Label(L("Remove from room"), systemImage: "person.fill.xmark")
                }
            }
            Divider()
            Button(role: .destructive) {
                settings.block(id, name: name)
                session.muteList = settings.muteList
            } label: {
                Label(L("Block"), systemImage: "hand.raised.slash")
            }
            Button {
                reporting = player
            } label: {
                Label(L("Report"), systemImage: "exclamationmark.bubble")
            }
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "ellipsis.circle")
                .font(.caption)
                .foregroundStyle(isMuted ? Ablox.Palette.danger : Ablox.Palette.inkFaint)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("More for {}", name))
    }

    private func pingBadge(_ ping: Double) -> some View {
        // Three bands rather than a raw number alone: "42ms" means nothing to
        // most players, a green dot does.
        let color: Color = ping < 60 ? Ablox.Palette.success
            : ping < 150 ? Ablox.Palette.warning
            : Ablox.Palette.danger
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(L("{}ms", Int(ping)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
