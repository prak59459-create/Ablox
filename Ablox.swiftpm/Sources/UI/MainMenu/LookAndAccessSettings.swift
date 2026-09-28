import SwiftUI
import GameController
import AbloxCore

// Settings → Look (light or dark, the accent colour), Settings → Seeing and
// hearing (colour vision, marks, VoiceOver), and Settings → Controllers.

// MARK: - Look

struct LookCard: View {
    @AppStorage(AbloxAppearance.key) private var appearance = AbloxAppearance.dark.rawValue
    @AppStorage(AbloxAccent.key) private var accent = AbloxAccent.cyan.rawValue

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(L("Look"), systemImage: "paintbrush.fill")

                Picker(L("Light or dark"), selection: $appearance) {
                    ForEach(AbloxAppearance.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(L("Accent colour"))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                HStack(spacing: 12) {
                    ForEach(AbloxAccent.allCases) { option in
                        Button {
                            // The cache first, then the stored value that
                            // rebuilds the screen.
                            AbloxAccent.current = option
                            accent = option.rawValue
                        } label: {
                            Circle()
                                .fill(LinearGradient(colors: [option.color, option.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(Ablox.Palette.ink, lineWidth: accent == option.rawValue ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.displayName)
                        .accessibilityAddTraits(accent == option.rawValue ? [.isSelected, .isButton] : .isButton)
                    }
                }

                Text(L("Games are always drawn dark, so their buttons show up over the world."))
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Seeing and hearing

struct AccessibilityCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(L("Seeing and hearing"), systemImage: "eye.circle")
                AccessOptionsSection()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Colour vision"))
                        .font(.subheadline.weight(.medium))
                    Picker(L("Colour vision"), selection: Binding(
                        get: { settings.preferences.colourVision },
                        set: { vision in
                            settings.preferences.colourVision = vision
                            // Help that does not depend on colour at all
                            // comes on with it.
                            if vision != .off { settings.preferences.markMeaning = true }
                        }
                    )) {
                        ForEach(ColourVision.allCases) { vision in
                            Text(vision.displayName).tag(vision)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(L("The game's picture is shifted so colours that look alike come apart."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    preview
                }

                Toggle(isOn: $settings.preferences.markMeaning) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Mark dangers and goals"))
                            .font(.subheadline.weight(.medium))
                        Text(L("Dangerous parts get stripes and goals get checks, so nothing is told by colour alone. From the next game."))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Ablox.Palette.accent)

                Toggle(isOn: $settings.preferences.readLinesAloud) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Read game lines aloud"))
                            .font(.subheadline.weight(.medium))
                        Text(L("What characters say is read out by the iPad."))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
                .tint(Ablox.Palette.accent)

                Label(L("With VoiceOver on, buttons, colours and the game's messages are read out. Moving around a 3D world still needs sight."),
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Red, green, blue and yellow as the chosen correction shows them.
    private var preview: some View {
        let colours = [ColorRGBA(hex: "#FF5A5F")!, ColorRGBA(hex: "#4ADE80")!, ColorRGBA(hex: "#3B82F6")!, ColorRGBA(hex: "#FFD60A")!]
        return HStack(spacing: 8) {
            ForEach(Array(colours.enumerated()), id: \.offset) { _, colour in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(colour)).frame(width: 36, height: 22)
                    RoundedRectangle(cornerRadius: 6).fill(Color(settings.preferences.colourVision.corrected(colour)))
                        .frame(width: 36, height: 22)
                }
            }
            Text(L("Top: as made. Bottom: as shown."))
                .font(.caption2)
                .foregroundStyle(Ablox.Palette.inkFaint)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Controllers

struct ControllersCard: View {
    @State private var devices: [String] = []

    private let changes = NotificationCenter.default.publisher(for: .GCControllerDidConnect)
        .merge(with: NotificationCenter.default.publisher(for: .GCControllerDidDisconnect),
               NotificationCenter.default.publisher(for: .GCKeyboardDidConnect),
               NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect),
               NotificationCenter.default.publisher(for: .GCMouseDidConnect),
               NotificationCenter.default.publisher(for: .GCMouseDidDisconnect))

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Controllers, keyboard and mouse"), systemImage: "gamecontroller.fill")

                if devices.isEmpty {
                    Text(L("Nothing connected. Pair a PlayStation or Xbox controller in the iPad's Settings → Bluetooth."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(devices, id: \.self) { device in
                        Label(device, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.success)
                    }
                }

                help(L("Controller"), [
                    L("Left stick: walk (all the way: run)"), L("Right stick: look"), L("A / ✕: jump"),
                    L("R2: fire"), L("L1: run"), L("Menu / Options: pause"), L("D-pad up and down: zoom")
                ])
                help(L("Keyboard"), [
                    L("W A S D: walk"), L("Space: jump"), L("Shift: run"), L("F: fire"), L("Arrow keys: look"), L("Esc or Tab: pause")
                ])
                help(L("Mouse or trackpad"), [
                    L("Hold the right button and move: look"), L("Scroll: zoom"), L("Click: the same as a tap")
                ])
            }
        }
        .onAppear(perform: refresh)
        .onReceive(changes) { _ in refresh() }
    }

    private func refresh() {
        var found = GCController.controllers().map { $0.vendorName ?? L("Game controller") }
        if GCKeyboard.coalesced != nil { found.append(L("Keyboard")) }
        if !GCMouse.mice().isEmpty { found.append(L("Mouse or trackpad")) }
        devices = found
    }

    private func help(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Ablox.Palette.ink)
            ForEach(lines, id: \.self) { line in
                Text(verbatim: "• " + line).font(.caption).foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
