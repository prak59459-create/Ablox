import Foundation
import Combine

/// The games' saved progress on this iPad, and the backup file that carries
/// everything to another one.
///
/// A thin observable layer over `GameSaveStore` (which the session writes to
/// while playing) so Settings can list and delete saves, and over
/// `AbloxBackup` so it can write and read a backup file.
@MainActor
public final class GameSaves: ObservableObject {

    @Published public private(set) var summaries: [GameSaveStore.Summary] = []
    @Published public private(set) var lastMessage: String?

    public let store: GameSaveStore

    public init(directory: URL = GameSaveStore.defaultDirectory) {
        store = GameSaveStore(directory: directory)
        reload()
    }

    public func reload() {
        summaries = store.summaries()
    }

    public func delete(_ summary: GameSaveStore.Summary) {
        store.delete(worldID: summary.id)
        reload()
    }

    public func deleteAll() {
        store.deleteAll()
        reload()
    }

    // MARK: Backup file

    /// Writes a backup to a temporary file for the share sheet, or nil (with
    /// `lastMessage` saying why).
    public func makeBackup(settings: AppSettings, worlds: ProjectStore) -> URL? {
        let backup = AbloxBackup(profile: settings.profile, wallet: settings.wallet,
                                 saves: store.allRecords, worlds: worlds.allWorlds())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(AbloxBackup.suggestedFileName())
        do {
            try backup.encoded().write(to: url, options: [.atomic])
            lastMessage = nil
            return url
        } catch {
            lastMessage = L("The backup could not be written: {}", error.localizedDescription)
            return nil
        }
    }

    // MARK: Before an update

    /// Application Support/Backups: copies kept inside the app, made by
    /// themselves before an update is handed over. Not Caches — the system
    /// may empty that whenever it likes.
    private static var keptBackups: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Backups", isDirectory: true)
    }

    /// A backup for the share sheet, with a copy also kept inside the app.
    /// Only the newest three kept copies stay.
    public func makeBackupBeforeUpdate(settings: AppSettings, worlds: ProjectStore) -> URL? {
        guard let url = makeBackup(settings: settings, worlds: worlds) else { return nil }
        let manager = FileManager.default
        let folder = Self.keptBackups
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let kept = folder.appendingPathComponent(url.lastPathComponent)
        try? manager.removeItem(at: kept)
        try? manager.copyItem(at: url, to: kept)
        let old = keptBackupFiles.dropFirst(3)
        for file in old { try? manager.removeItem(at: file) }
        return url
    }

    /// The copies kept inside the app, newest first.
    public var keptBackupFiles: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.keptBackups, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files.filter { $0.pathExtension == AbloxBackup.fileExtension }.sorted { date($0) > date($1) }
    }

    /// Reads a backup chosen in Files and merges it in: newer saves and
    /// worlds win, coins never go down, the avatar comes back.
    public func restoreBackup(from url: URL, settings: AppSettings, worlds: ProjectStore) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let backup = try AbloxBackup.decoded(from: data)
            let saves = store.merge(backup.saves)
            let restoredWorlds = worlds.merge(backup.worlds)
            settings.wallet = settings.wallet.merged(with: backup.wallet)
            settings.profile = backup.profile
            reload()
            lastMessage = L("Restored: {} saved games and {} worlds.", saves, restoredWorlds)
        } catch let error as AbloxBackup.ReadError {
            lastMessage = error.errorDescription
        } catch {
            lastMessage = L("That file could not be read: {}", error.localizedDescription)
        }
    }
}
