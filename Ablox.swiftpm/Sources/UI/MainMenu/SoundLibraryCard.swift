import SwiftUI
import AbloxCore

/// Settings → Sound library: how many of the library's sounds are on this
/// iPad, and the way into the library itself.
struct SoundLibraryCard: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var store = SoundLibraryStore.shared
    @State private var showing = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(L("Sound library"), systemImage: "speaker.wave.3.fill")
                Text(L("Over 6,000 sound effects for games: coins, jumps, animals, doors, explosions, magic… Listen to them, copy a name into a script, or download every one to play without the internet."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let library = store.library {
                    Text(L("{} of {} sounds on this iPad · {}", store.installed.count, library.soundCount, Megabytes.text(store.installedBytes)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
                Button {
                    showing = true
                } label: {
                    Label(L("Open the sound library"), systemImage: "music.note.list")
                }
                .buttonStyle(NeonButtonStyle(.primary))
            }
        }
        .onAppear { store.source = settings.catalogueSource }
        .sheet(isPresented: $showing) {
            SoundLibraryView(source: settings.catalogueSource)
        }
    }
}
