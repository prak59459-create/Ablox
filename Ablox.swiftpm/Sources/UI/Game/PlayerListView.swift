import SwiftUI

/// Who is in the session: name, score, role and latency, with a mute control.
///
/// Muting lives here rather than only on a chat message because the moment
/// you want it is usually *after* the message has scrolled away.
struct PlayerListView: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings

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
    }

    private func row(_ player: PlayerSnapshot) -> some View {
        let isSelf = player.peerID == session.localPeerID
        let isHost = session.role == .hosting && isSelf
        let isMuted = settings.muteList.isMuted(player.peerID)

        return HStack(spacing: 9) {
            Circle()
                .fill(Color(player.profile.bodyColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 0) {
                Text(player.profile.displayName)
                    .font(.subheadline.weight(isSelf ? .bold : .regular))
                    .foregroundStyle(isMuted ? Ablox.Palette.inkFaint : Ablox.Palette.ink)
                    .lineLimit(1)
                    .strikethrough(isMuted, color: Ablox.Palette.inkFaint)
                if isHost {
                    Text(L("Host"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ablox.Palette.success)
                }
            }

            Spacer(minLength: 8)

            Text("\(player.score)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Ablox.Palette.accent)

            // You cannot mute yourself — see MuteList.allows(_:localPeerID:).
            if !isSelf {
                Button {
                    settings.muteList.toggle(player.peerID)
                    session.muteList = settings.muteList
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(isMuted ? Ablox.Palette.danger : Ablox.Palette.inkFaint)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMuted ? "Unmute \(player.profile.displayName)" : "Mute \(player.profile.displayName)")
            }
        }
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
