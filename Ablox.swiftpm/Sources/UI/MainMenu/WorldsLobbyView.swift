import SwiftUI

/// The world library: create, play, host, and (on a device with Ablox Studio
/// installed) hand off for editing.
struct WorldsLobbyView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    var onEnter: (ActiveSession) -> Void

    @State private var isCreating = false
    @State private var newWorldName = ""
    @State private var selectedTemplate: ProjectStore.Template = .starter
    @State private var pendingDeletion: ProjectStore.Entry?
    @State private var renaming: ProjectStore.Entry?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let error = store.lastError {
                    GlassCard {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Ablox.Palette.warning)
                            .font(.subheadline)
                    }
                }

                if store.entries.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            title: "Your library is empty",
                            message: "Make a world to play in. The obstacle-course template already has a spawn point, stairs, a coin and a finish line.",
                            systemImage: "square.stack.3d.up"
                        )
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 15)], spacing: 15) {
                        ForEach(store.entries) { entry in
                            worldCard(entry)
                        }
                    }
                }
            }
            .padding(Ablox.Metrics.gutter)
        }
        .sheet(isPresented: $isCreating) { createSheet }
        .alert(L("Delete this world?"), isPresented: .constant(pendingDeletion != nil)) {
            Button(L("Cancel"), role: .cancel) { pendingDeletion = nil }
            Button(L("Delete"), role: .destructive) {
                if let pendingDeletion { store.delete(pendingDeletion) }
                pendingDeletion = nil
            }
        } message: {
            Text(L("“{}” will be removed from this iPad. This cannot be undone.", pendingDeletion?.name ?? ""))
        }
        .alert(L("Rename world"), isPresented: .constant(renaming != nil)) {
            TextField(L("Name"), text: $renameText)
            Button(L("Cancel"), role: .cancel) { renaming = nil }
            Button(L("Rename")) {
                if let renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.rename(renaming, to: renameText)
                }
                renaming = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Worlds"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Ablox.Palette.ink)
                Text(L("Play them solo, or host one and let friends join from the Play tab."))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            Spacer()
            Button {
                newWorldName = store.uniqueName(basedOn: "My World")
                selectedTemplate = .starter
                isCreating = true
            } label: {
                Label(L("New world"), systemImage: "plus")
            }
            .buttonStyle(NeonButtonStyle(.primary))
        }
    }

    private func worldCard(_ entry: ProjectStore.Entry) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Ablox.Palette.brand.opacity(0.9))
                            .frame(width: 42, height: 42)
                        Image(systemName: "cube.fill").foregroundStyle(.black)
                    }
                    Spacer()
                    Menu {
                        Button {
                            renameText = entry.name
                            renaming = entry
                        } label: { Label(L("Rename"), systemImage: "pencil") }

                        Button {
                            store.duplicate(entry)
                        } label: { Label(L("Duplicate"), systemImage: "doc.on.doc") }

                        Divider()

                        Button(role: .destructive) {
                            pendingDeletion = entry
                        } label: { Label(L("Delete"), systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .frame(width: Ablox.Metrics.minimumTapTarget, height: Ablox.Metrics.minimumTapTarget, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(Ablox.Palette.ink)
                        .lineLimit(1)
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }

                HStack(spacing: 9) {
                    Button {
                        guard let world = store.load(entry) else { return }
                        onEnter(ActiveSession(mode: .solo(world)))
                    } label: {
                        Label(L("Play"), systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonButtonStyle(.primary, fullWidth: true))

                    Button {
                        guard let world = store.load(entry) else { return }
                        onEnter(ActiveSession(mode: .hosting(world)))
                    } label: {
                        Label(L("Host"), systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
                }
            }
        }
    }

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L("New world"))
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 7) {
                Text(L("Name")).font(.caption.weight(.semibold)).foregroundStyle(Ablox.Palette.inkMuted)
                TextField(L("My World"), text: $newWorldName)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(L("Start from")).font(.caption.weight(.semibold)).foregroundStyle(Ablox.Palette.inkMuted)
                ForEach(ProjectStore.Template.allCases) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: template.symbolName)
                                .font(.title3)
                                .frame(width: 30)
                                .foregroundStyle(selectedTemplate == template ? Ablox.Palette.accent : Ablox.Palette.inkMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.displayName)
                                    .font(.headline)
                                    .foregroundStyle(Ablox.Palette.ink)
                                Text(template.detail)
                                    .font(.caption)
                                    .foregroundStyle(Ablox.Palette.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: selectedTemplate == template ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTemplate == template ? Ablox.Palette.accent : Ablox.Palette.inkFaint)
                        }
                        .padding(13)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(selectedTemplate == template ? Ablox.Palette.accent.opacity(0.55) : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 11) {
                Button(L("Cancel")) { isCreating = false }
                    .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
                Button(L("Create")) {
                    let name = newWorldName.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = store.createWorld(
                        named: name.isEmpty ? "My World" : name,
                        template: selectedTemplate,
                        author: settings.profile.displayName
                    )
                    isCreating = false
                }
                .buttonStyle(NeonButtonStyle(.primary, fullWidth: true))
            }
        }
        .padding(26)
        .frame(maxWidth: 520)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}
