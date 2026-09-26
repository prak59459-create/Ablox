import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showingVersions: ProjectStore.Entry?
    @State private var showingDeleted = false
    /// The world waiting for the host to pick public or private. Kept apart
    /// from the dialog's own flag, so closing the dialog cannot clear it
    /// before the chosen button reads it.
    @State private var hostCandidate: WorldDocument?
    @State private var askingVisibility = false
    @State private var importing = false
    @State private var sharing: SharedFile?
    @State private var filingInNewFolder: ProjectStore.Entry?
    @State private var newFolderName = ""
    @State private var folderFilter: String?
    @AppStorage("ablox.worldSort") private var sort: WorldSort = .newest

    /// How the library is ordered.
    enum WorldSort: String, CaseIterable, Identifiable {
        case newest, name, size
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newest: return L("Last changed")
            case .name: return L("Name")
            case .size: return L("Biggest")
            }
        }
    }

    /// The worlds to show: in the chosen folder, in the chosen order.
    private var shown: [ProjectStore.Entry] {
        // A folder emptied since it was chosen shows everything again.
        let folder = folderFilter.flatMap { store.folderNames.contains($0) ? $0 : nil }
        let inFolder = store.entries.filter { folder == nil || store.folders[$0.id] == folder }
        switch sort {
        case .newest: return inFolder
        case .name: return inFolder.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: return inFolder.sorted { $0.blockCount > $1.blockCount }
        }
    }

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
                    shelfBar
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 15)], spacing: 15) {
                        ForEach(shown) { entry in
                            worldCard(entry)
                        }
                    }
                }
            }
            .padding(Ablox.Metrics.gutter)
        }
        .background(
            Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.data, .json], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls { store.importWorld(from: url) }
            }
        )
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
        .sheet(isPresented: $isCreating) { createSheet }
        .sheet(item: $showingVersions) { entry in
            WorldVersionsSheet(entry: entry).environmentObject(store)
        }
        .sheet(isPresented: $showingDeleted) {
            RecentlyDeletedSheet().environmentObject(store)
        }
        .roomVisibilityDialog(isPresented: $askingVisibility, allowsPublic: settings.parental.allowPublicRooms) { isPublic in
            if let world = hostCandidate {
                onEnter(ActiveSession(mode: .hosting(world, isPublic: isPublic)))
            }
            hostCandidate = nil
        }
        .alert(L("Delete this world?"), isPresented: .constant(pendingDeletion != nil)) {
            Button(L("Cancel"), role: .cancel) { pendingDeletion = nil }
            Button(L("Delete"), role: .destructive) {
                if let pendingDeletion { store.delete(pendingDeletion) }
                pendingDeletion = nil
            }
        } message: {
            Text(L("“{}” moves to Recently Deleted, where it can be put back for 30 days.", pendingDeletion?.name ?? ""))
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
            if !store.deleted.isEmpty {
                Button { showingDeleted = true } label: {
                    Label(L("Recently deleted"), systemImage: "trash")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
            Button { importing = true } label: {
                Label(L("Add from Files"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(NeonButtonStyle(.secondary))
            Button {
                newWorldName = store.uniqueName(basedOn: "My World")
                selectedTemplate = .starter
                isCreating = true
            } label: {
                Label(L("New world"), systemImage: "plus")
            }
            .buttonStyle(NeonButtonStyle(.primary))
        }
        // Kept on the header so it never shares a view with the other alerts.
        .alert(L("New folder"), isPresented: .constant(filingInNewFolder != nil)) {
            TextField(L("Folder name"), text: $newFolderName)
            Button(L("Cancel"), role: .cancel) { filingInNewFolder = nil }
            Button(L("Add")) {
                if let entry = filingInNewFolder { store.setFolder(newFolderName, for: entry) }
                filingInNewFolder = nil
            }
        }
    }

    /// Folders to look in, and the order.
    private var shelfBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker(L("Order"), selection: $sort) {
                        ForEach(WorldSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                if !store.folderNames.isEmpty {
                    folderChip(nil, title: L("All worlds"))
                    ForEach(store.folderNames, id: \.self) { name in
                        folderChip(name, title: name)
                    }
                }
            }
        }
    }

    private func folderChip(_ folder: String?, title: String) -> some View {
        let chosen = folderFilter.flatMap { store.folderNames.contains($0) ? $0 : nil }
        let on = chosen == folder
        return Button {
            folderFilter = folder
        } label: {
            Label(title, systemImage: folder == nil ? "square.stack.3d.up" : "folder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.black : Ablox.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(on ? AnyShapeStyle(Ablox.Palette.accent) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func worldCard(_ entry: ProjectStore.Entry) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                ZStack(alignment: .topTrailing) {
                    WorldThumbnail(store: store, id: entry.id, name: entry.name)
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Menu {
                        let isLocked = store.locked.contains(entry.id)
                        Button {
                            renameText = entry.name
                            renaming = entry
                        } label: { Label(L("Rename"), systemImage: "pencil") }
                        .disabled(isLocked)

                        Button {
                            store.duplicate(entry)
                        } label: { Label(L("Duplicate"), systemImage: "doc.on.doc") }

                        Button {
                            showingVersions = entry
                        } label: { Label(L("Earlier versions"), systemImage: "clock.arrow.circlepath") }

                        Button {
                            if let url = store.shareableCopy(of: entry) { sharing = SharedFile(url: url) }
                        } label: { Label(L("Send this world"), systemImage: "square.and.arrow.up") }

                        Menu {
                            ForEach(store.folderNames, id: \.self) { name in
                                Button {
                                    store.setFolder(name, for: entry)
                                } label: {
                                    if store.folders[entry.id] == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                                }
                            }
                            Button {
                                newFolderName = ""
                                filingInNewFolder = entry
                            } label: { Label(L("New folder…"), systemImage: "folder.badge.plus") }
                            if store.folders[entry.id] != nil {
                                Button {
                                    store.setFolder(nil, for: entry)
                                } label: { Label(L("Take out of the folder"), systemImage: "folder.badge.minus") }
                            }
                        } label: { Label(L("Folder"), systemImage: "folder") }

                        Button {
                            store.setLocked(!isLocked, entry)
                        } label: {
                            Label(isLocked ? L("Unlock") : L("Lock so it can't be deleted"), systemImage: isLocked ? "lock.open" : "lock")
                        }

                        Divider()

                        Button(role: .destructive) {
                            pendingDeletion = entry
                        } label: { Label(L("Delete"), systemImage: "trash") }
                        .disabled(isLocked)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.45), in: Circle())
                            .frame(width: Ablox.Metrics.minimumTapTarget, height: Ablox.Metrics.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("More"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if store.locked.contains(entry.id) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(Ablox.Palette.warning)
                                .accessibilityLabel(L("Locked"))
                        }
                        Text(entry.name)
                            .font(.headline)
                            .foregroundStyle(Ablox.Palette.ink)
                            .lineLimit(1)
                    }
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                    if let folder = store.folders[entry.id] {
                        Label(folder, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.inkFaint)
                    }
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
                        hostCandidate = world
                        askingVisibility = true
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
