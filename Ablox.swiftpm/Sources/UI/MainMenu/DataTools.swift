import SwiftUI
import UniformTypeIdentifiers

// Settings → Saved data, the tools: a backup that writes itself to a folder
// in Files once a day, one game's save as a file, what is using space (and
// clearing what can come back), and moving everything to another iPad.

// MARK: - Automatic backup

@MainActor
enum AutoBackup {
    /// The file written in the chosen folder, replaced each time.
    static let fileName = "Ablox Auto Backup." + AbloxBackup.fileExtension

    /// Remembers a folder chosen in Files, so later backups can go there
    /// without asking.
    static func choose(folder url: URL, settings: AppSettings) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        settings.memory.autoBackupBookmark = bookmark
        settings.memory.lastAutoBackup = nil
        return true
    }

    /// The chosen folder's name, for Settings.
    static func folderName(settings: AppSettings) -> String? {
        guard let bookmark = settings.memory.autoBackupBookmark else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.lastPathComponent
    }

    /// Once a day, when a folder has been chosen: writes a fresh backup
    /// there. Quiet about failures — the folder may be on iCloud and away.
    static func runIfDue(settings: AppSettings, saves: GameSaves, store: ProjectStore, force: Bool = false) {
        guard let bookmark = settings.memory.autoBackupBookmark else { return }
        if !force, let last = settings.memory.lastAutoBackup, Date().timeIntervalSince(last) < 86_400 { return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let made = saves.makeBackup(settings: settings, worlds: store) else { return }
        let target = folder.appendingPathComponent(fileName)
        let manager = FileManager.default
        try? manager.removeItem(at: target)
        guard (try? manager.copyItem(at: made, to: target)) != nil else { return }
        settings.memory.lastAutoBackup = Date()
        if stale, let fresh = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.memory.autoBackupBookmark = fresh
        }
    }
}

// MARK: - One game's save

extension GameSaves {
    /// One game's saved progress as a small file, to send to someone or keep.
    func exportSave(_ summary: GameSaveStore.Summary) -> URL? {
        guard let record = store.record(for: summary.id),
              let data = try? GameSaveStore.encoder.encode(record) else { return nil }
        let safe = summary.worldName.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).abloxsave")
        return (try? data.write(to: url, options: [.atomic])) != nil ? url : nil
    }

    /// Reads a game's save file and keeps it, unless the one here is newer.
    func importSave(from url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count < 256 * 1024,
              let record = try? GameSaveStore.decoder.decode(GameSaveStore.Record.self, from: data) else {
            return L("That file is not a saved game.")
        }
        let changed = store.merge([record])
        reload()
        return changed > 0 ? L("Saved game for “{}” added.", record.worldName) : L("The save here for “{}” is newer, so it was kept.", record.worldName)
    }
}

// MARK: - Space

/// How much each kind of thing takes, and clearing what downloads again.
struct StorageCard: View {
    @State private var sizes: [(String, Int64)] = []
    @State private var cleared = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L("Space used"), systemImage: "internaldrive")
                ForEach(sizes.indices, id: \.self) { index in
                    HStack {
                        Text(sizes[index].0)
                            .font(.subheadline)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: sizes[index].1, countStyle: .file))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                }
                Button {
                    Self.clearCaches()
                    cleared = true
                    measure()
                } label: {
                    Label(L("Clear downloads and caches"), systemImage: "trash")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
                Text(cleared
                     ? L("Cleared. Games download again when you next play them.")
                     : L("Downloaded games, covers and updates come back by themselves when needed. Your worlds, saves and pictures are not touched."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: measure)
    }

    private func measure() {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let rows: [(String, URL?)] = [
            (L("Worlds"), support?.appendingPathComponent("Worlds")),
            (L("Saved games"), support?.appendingPathComponent("Saves")),
            (L("Backups kept here"), support?.appendingPathComponent("Backups")),
            (L("Pictures and clips"), ScreenshotStore.folder),
            (L("Downloads and caches"), caches)
        ]
        sizes = rows.map { ($0.0, $0.1.map(Self.size(of:)) ?? 0) }
    }

    static func size(of folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Removes the files but keeps the folders: the game list and the
    /// updater made theirs when the app started and write into them without
    /// making them again.
    static func clearCaches() {
        URLCache.shared.removeAllCachedResponses()
        let manager = FileManager.default
        guard let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let walker = manager.enumerator(at: caches, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        var files: [URL] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            files.append(url)
        }
        for file in files { try? manager.removeItem(at: file) }
    }
}

// MARK: - Moving to another iPad

/// Everything to a new iPad in three steps.
struct MoveWizardSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var saves: GameSaves
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var backup: URL?
    @State private var sharing: SharedFile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    step(1, L("On this iPad: make a backup of everything."), done: backup != nil) {
                        Button {
                            backup = saves.makeBackup(settings: settings, worlds: store)
                        } label: {
                            Label(backup == nil ? L("Make the backup") : L("Made"), systemImage: "externaldrive.badge.plus")
                        }
                        .buttonStyle(NeonButtonStyle(.primary))
                    }
                    step(2, L("Send it: AirDrop it to the new iPad, or save it to Files (iCloud Drive) to open there."), done: false) {
                        Button {
                            if let backup { sharing = SharedFile(url: backup) }
                        } label: {
                            Label(L("Send the backup"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(NeonButtonStyle(.primary))
                        .disabled(backup == nil)
                    }
                    step(3, L("On the new iPad: open Ablox, go to Settings → Saved data, tap “Restore from a backup” and choose the file."), done: false) {
                        EmptyView()
                    }
                    Text(L("Your avatar, coins, saved games and worlds all come across. Nothing is deleted from this iPad."))
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                .padding(24)
            }
            .navigationTitle(L("Move to another iPad"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
    }

    private func step<Content: View>(_ number: Int, _ text: String, done: Bool, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle.fill")
                .font(.title)
                .foregroundStyle(done ? Ablox.Palette.success : Ablox.Palette.accent)
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }
}
