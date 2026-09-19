import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Settings"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(L("Controls, feel, and what Ablox is doing on your network."))
                        .font(.subheadline)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }

                languageCard
                controlsCard
                movementCard
                networkCard
                aboutCard
            }
            .padding(Ablox.Metrics.gutter)
            .frame(maxWidth: 780, alignment: .leading)
        }
    }

    // MARK: Language

    /// First card on the screen on purpose: it is the one setting someone who
    /// cannot read the others still has to be able to find.
    private var languageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(L("Language"), systemImage: "globe")

                Picker(L("Language"), selection: $settings.language) {
                    ForEach(LanguagePreference.allCases) { preference in
                        // Each row is written in the language it selects, so
                        // the Japanese one reads as Japanese even now.
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text(L("Ablox Studio has the same setting."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
        }
    }

    // MARK: Controls

    private var controlsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 17) {
                SectionHeader(L("Controls"), systemImage: "hand.draw.fill")

                Toggle(isOn: $settings.joystickOnRight) {
                    settingLabel(L("Joystick on the right"), L("Swaps the stick and the camera area. For left-handed players."))
                }
                .tint(Ablox.Palette.accent)

                Toggle(isOn: $settings.invertCameraY) {
                    settingLabel(L("Invert camera up/down"), L("Drag down to look up."))
                }
                .tint(Ablox.Palette.accent)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        settingLabel(L("Camera sensitivity"), L("How far the view turns for one swipe."))
                        Spacer()
                        Text(String(format: "%.1f×", settings.cameraSensitivity))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Ablox.Palette.accent)
                    }
                    Slider(value: $settings.cameraSensitivity, in: 0.4...2.5)
                        .tint(Ablox.Palette.accent)
                }

                Toggle(isOn: $settings.soundEnabled) {
                    settingLabel(L("Sound effects"), nil)
                }
                .tint(Ablox.Palette.accent)

                Toggle(isOn: $settings.hapticsEnabled) {
                    settingLabel(L("Haptics"), L("A tap when you collect something or hit a checkpoint."))
                }
                .tint(Ablox.Palette.accent)
            }
        }
    }

    // MARK: Movement

    private var movementCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 17) {
                SectionHeader(L("Movement"), systemImage: "figure.run") {
                    Button(L("Reset")) { settings.resetToDefaults() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Ablox.Palette.accent)
                }

                slider("Walk speed", value: $settings.movement.walkSpeed, range: 2...10, unit: "m/s")
                slider("Jump height", value: $settings.movement.jumpSpeed, range: 3...11, unit: "m/s")
                slider("Gravity", value: $settings.movement.gravity, range: -40...(-6), unit: "m/s²")

                Text(L("These change how your own avatar feels. The world's own gravity still applies to blocks."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ablox.Palette.ink)
                Spacer()
                Text(String(format: "%.1f %@", value.wrappedValue, unit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ablox.Palette.accent)
            }
            Slider(value: value, in: range).tint(Ablox.Palette.accent)
        }
    }

    // MARK: Network

    private var networkCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(L("Network"), systemImage: "lock.shield.fill")

                infoRow(L("Service"), AbloxProtocol.bonjourServiceType, symbol: "bonjour")
                infoRow(L("Transport"), L("TCP over TLS 1.3, pre-shared key"), symbol: "lock.fill")
                infoRow(L("Discovery"), L("Bonjour, plus direct peer-to-peer"), symbol: "antenna.radiowaves.left.and.right")
                infoRow(L("Protocol version"), String(AbloxProtocol.version), symbol: "number")
                infoRow(L("This iPad"), session.localPeerID.description, symbol: "ipad")

                Divider().background(Color.white.opacity(0.08))

                Text(L("Ablox never sends anything to a server. Worlds and player positions travel directly between iPads on your local network, encrypted with a key derived from the room code the host shows you. Anyone who knows that code can join and can read that session's traffic, so share it only with the people you want in the world."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.footnote)
                .frame(width: 20)
                .foregroundStyle(Ablox.Palette.accent)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(Ablox.Palette.ink)
        }
    }

    // MARK: About

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 11) {
                SectionHeader(L("About"), systemImage: "info.circle.fill")
                Text(L("Ablox is a sandbox you build and play with friends in the same room. Build worlds in Ablox Studio, then host them here."))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Made with SwiftUI, RealityKit and Network.framework. No third-party code."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
        }
    }

    private func settingLabel(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Ablox.Palette.ink)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
