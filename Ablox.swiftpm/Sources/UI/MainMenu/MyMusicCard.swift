import SwiftUI
import UniformTypeIdentifiers
import AbloxCore

/// Settings → My music: songs of the player's own, from the Files app, for
/// the Plaza and for games (`MyMusic`).
struct MyMusicCard: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var songs = MyMusicPlayer.shared
    @State private var choosing = false
    @State private var problem: String?
    @State private var listening: UUID?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(L("My music"), systemImage: "music.note")
                Text(L("Add songs you made (or may use) from the Files app, and play them in the Plaza or in games. Only you hear them; they stay on this iPad."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(songs.tracks) { track in
                    row(track)
                }

                if !songs.tracks.isEmpty {
                    Picker(L("In the Plaza"), selection: $settings.preferences.plazaSong) {
                        Text(L("Ablox music")).tag(UUID?.none)
                        ForEach(songs.tracks) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Picker(L("In games"), selection: $settings.preferences.gameSong) {
                        Text(L("The game's own music")).tag(UUID?.none)
                        ForEach(songs.tracks) { Text($0.title).tag(Optional($0.id)) }
                    }
                }

                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    choosing = true
                } label: {
                    Label(L("Add a song"), systemImage: "plus")
                }
                .buttonStyle(NeonButtonStyle(.primary))
                .disabled(songs.tracks.count >= MyMusic.maximumTracks)
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            problem = urls.compactMap { songs.add(from: $0) }.first
        }
        .onDisappear {
            if listening != nil { songs.stop() }
            listening = nil
        }
    }

    private func row(_ track: MyMusic.Track) -> some View {
        HStack(spacing: 11) {
            Button {
                if listening == track.id {
                    songs.stop()
                    listening = nil
                } else {
                    songs.play(track.id, volume: Float(settings.preferences.musicVolume))
                    listening = track.id
                }
            } label: {
                Image(systemName: listening == track.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ablox.Palette.accent)
            .accessibilityLabel(listening == track.id ? L("Stop") : L("Listen"))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(Megabytes.text(track.bytes))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
            Spacer()
            Button(role: .destructive) {
                if listening == track.id { listening = nil }
                if settings.preferences.plazaSong == track.id { settings.preferences.plazaSong = nil }
                if settings.preferences.gameSong == track.id { settings.preferences.gameSong = nil }
                songs.delete(track.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ablox.Palette.inkMuted)
            .accessibilityLabel(L("Delete"))
        }
    }
}
