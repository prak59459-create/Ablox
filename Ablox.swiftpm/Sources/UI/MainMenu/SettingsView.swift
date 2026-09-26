import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var saves: GameSaves
    @EnvironmentObject private var updater: AppUpdater

    @State private var deletingSave: GameSaveStore.Summary?
    @State private var confirmingDeleteAll = false
    @State private var backupFile: BackupFile?
    @State private var choosingBackup = false
    @State private var installing: UpdateInstall?

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
                UpdateSettingsCard(updater: updater) {
                    installing = UpdateInstall(backup: saves.makeBackupBeforeUpdate(settings: settings, worlds: store))
                }
                FamilyCard()
                gamesCard
                dataCard
                ComfortCard()
                graphicsCard
                controlsCard
                movementCard
                networkCard
                aboutCard
            }
            .padding(Ablox.Metrics.gutter)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .sheet(item: $installing) { install in
            UpdateInstallSheet(updater: updater, backup: install.backup)
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

    // MARK: Games

    /// Which repository the Games tab reads.
    ///
    /// Here rather than hidden, because a school or a club running its own
    /// list is a reasonable thing to want, and because someone should be able
    /// to see where their iPad is fetching from.
    private var gamesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(L("Game list"), systemImage: "square.stack.3d.up.fill")

                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Which GitHub repository the Games tab reads."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        repositoryField("owner/repo", text: $settings.catalogueRepository)
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                        repositoryField("main", text: $settings.catalogueBranch)
                            .frame(maxWidth: 170)
                    }
                }

                // Shown rather than enforced by rejecting keystrokes: someone
                // mid-way through typing a valid name has not made a mistake.
                if !CatalogueSource(repository: settings.catalogueRepository
                    .trimmingCharacters(in: .whitespacesAndNewlines)).isValidRepository {
                    Label(L("That is not a repository name. Using the built-in list."), systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.warning)
                } else if !CatalogueSource.isValidReference(settings.catalogueBranch
                    .trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Label(L("That is not a branch name. Using main."), systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.warning)
                }

                Text(L("Only worlds are downloaded, and only from this repository. Nothing is uploaded."))
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func repositoryField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .font(.callout.monospaced())
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Saved data

    /// What games have saved here, and the backup file that moves everything
    /// — avatar, coins, saves, worlds — to another iPad.
    private var dataCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(L("Saved data"), systemImage: "externaldrive.fill")

                Text(L("Games keep your progress — coins, quests, what you unlocked — on this iPad by themselves, even in a friend's room. It comes back next time you play the same game."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if saves.summaries.isEmpty {
                    Label(L("No game has saved anything yet."), systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                } else {
                    VStack(spacing: 8) {
                        ForEach(saves.summaries) { summary in
                            saveRow(summary)
                        }
                    }
                    Button(role: .destructive) { confirmingDeleteAll = true } label: {
                        Label(L("Delete all saved games"), systemImage: "trash")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ablox.Palette.danger)
                }

                Divider().background(Color.white.opacity(0.08))

                Text(L("A backup file holds your avatar, coins, saved games and worlds. Keep it in Files or send it to another iPad, then open it there with “Restore from a backup”."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        if let url = saves.makeBackup(settings: settings, worlds: store) { backupFile = BackupFile(url: url) }
                    } label: {
                        Label(L("Make a backup"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(NeonButtonStyle(.primary))

                    Button { choosingBackup = true } label: {
                        Label(L("Restore from a backup"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                }

                if let kept = saves.keptBackupFiles.first {
                    Button {
                        saves.restoreBackup(from: kept, settings: settings, worlds: store)
                    } label: {
                        Label(L("Bring back the backup made before the last update"), systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ablox.Palette.accent)
                }

                if let message = saves.lastMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { saves.reload() }
        .alert(L("Delete this saved game?"), isPresented: Binding(get: { deletingSave != nil }, set: { if !$0 { deletingSave = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletingSave = nil }
            Button(L("Delete"), role: .destructive) {
                if let deletingSave { saves.delete(deletingSave) }
                deletingSave = nil
            }
        } message: {
            Text(L("Your progress in “{}” will start again from nothing.", deletingSave?.worldName ?? ""))
        }
        .alert(L("Delete every saved game?"), isPresented: $confirmingDeleteAll) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete"), role: .destructive) { saves.deleteAll() }
        } message: {
            Text(L("Every game starts again from nothing. Worlds and coins are not touched."))
        }
        .sheet(item: $backupFile) { file in
            BackupShareSheet(url: file.url)
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.data, .json]) { result in
            if case let .success(url) = result {
                saves.restoreBackup(from: url, settings: settings, worlds: store)
            }
        }
    }

    private func saveRow(_ summary: GameSaveStore.Summary) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "gamecontroller.fill")
                .font(.footnote)
                .frame(width: 20)
                .foregroundStyle(Ablox.Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.worldName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ablox.Palette.ink)
                Text(summary.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            Spacer()
            Button { deletingSave = summary } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .frame(width: Ablox.Metrics.minimumTapTarget, height: Ablox.Metrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Delete"))
        }
    }

    // MARK: Graphics

    private var graphicsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(L("Graphics"), systemImage: "sparkles.tv")

                Picker(L("Graphics"), selection: $settings.graphicsQuality) {
                    ForEach(GraphicsQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.graphicsQuality.detail)
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $settings.showFrameRate) {
                    settingLabel(L("Show frame rate"), L("A small counter at the top of the screen while you play."))
                }
                .tint(Ablox.Palette.accent)
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

                Text(L("Play traffic never touches a server. Worlds and player positions travel directly between iPads on your local network, encrypted with a key derived from the room code the host shows you. Anyone who knows that code can join and can read that session's traffic, so share it only with the people you want in the world. There are two exceptions, and both only read from public GitHub repositories: the Games tab downloads published worlds, and a world set to get its scripts from GitHub fetches them when you host it. Nothing about you is sent."))
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

/// A backup written and waiting to be shared.
private struct BackupFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct BackupShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(Ablox.Palette.accent)
            Text(verbatim: url.lastPathComponent)
                .font(.headline.monospaced())
                .multilineTextAlignment(.center)
            Text(L("Save it to Files, or AirDrop it to the iPad you are moving to."))
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)
                .multilineTextAlignment(.center)
            ShareLink(item: url) {
                Label(L("Share or save to Files"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(NeonButtonStyle(.primary))
            Button(L("Done")) { dismiss() }
                .buttonStyle(NeonButtonStyle(.secondary))
        }
        .padding(30)
        .presentationDetents([.medium])
    }
}
