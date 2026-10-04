import SwiftUI

// Access, the second round: bold text and less motion everywhere, a word
// on screen for each sound, a gentler pace, asking before leaving, which
// tab opens first — and the options that choose them. Rules in
// AbloxCore/FamilyExtras.swift (`AccessOptions`).

extension View {
    /// Bold text and less motion, as chosen, for everything inside.
    func abloxAccess(_ options: AccessOptions) -> some View {
        self
            .bold(options.boldText)
            .transaction { transaction in
                if options.reduceMotion { transaction.animation = nil }
            }
    }
}

/// The last few sounds, as words, at the top of the play screen.
struct SoundCaptionsView: View {
    let captions: [SoundCaption]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(captions) { caption in
                Label(caption.text, systemImage: caption.important ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(caption.important ? Ablox.Palette.warning.opacity(0.85) : Color.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(caption.important ? .black : .white)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One sound, shown for a moment.
struct SoundCaption: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let important: Bool
    let shownAt: Date
}

/// Access options, in Settings → Seeing and hearing.
struct AccessOptionsSection: View {
    @EnvironmentObject private var settings: AppSettings

    private var access: Binding<AccessOptions> { $settings.preferences.access }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L("Bold text"), isOn: access.boldText)
            Toggle(L("Less motion in the menus"), isOn: access.reduceMotion)
            Toggle(L("Words on screen for sounds"), isOn: access.soundCaptions)
            Toggle(L("A tap felt for important sounds"), isOn: access.vibrateImportant)
            Toggle(L("The screen flashes for important sounds"), isOn: access.flashImportant)
            Toggle(L("Messages stay on screen longer"), isOn: access.longerMessages)
            Toggle(L("Read each tab's name aloud"), isOn: access.readTabsAloud)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Walking speed"))
                    .font(.subheadline.weight(.medium))
                Slider(value: access.movementSpeed, in: AccessOptions.movementRange)
                Text(settings.preferences.access.movementSpeed < 0.99
                     ? L("A gentler pace: {}% of the usual.", Int((settings.preferences.access.movementSpeed * 100).rounded()))
                     : L("The usual pace."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            Toggle(L("Ask before leaving a game"), isOn: access.confirmLeaving)
            Picker(L("Open Ablox on"), selection: Binding(
                get: { MenuTab(rawValue: settings.preferences.access.startTab ?? "") ?? .play },
                set: { settings.preferences.access.startTab = $0.rawValue })) {
                ForEach(MenuTab.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .tint(Ablox.Palette.accent)
    }
}
