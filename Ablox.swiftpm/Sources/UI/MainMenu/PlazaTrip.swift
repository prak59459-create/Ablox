import SwiftUI
import AbloxCore

/// A visit to the Plaza (Ablox NEXT, step 5). The world is made from the
/// game list as it is opened — the games this player may play, with their
/// covers on the doors — and walking into a door leaves the Plaza for the
/// page behind it. The browser version does the same (web/src/app/plaza.ts
/// in AbloxGames).
@MainActor
final class PlazaTrip: ObservableObject {
    /// Making the Plaza: the list and the covers are being read.
    @Published private(set) var isOpening = false
    private var doors: [UUID: PlazaWorld.Door] = [:]
    /// The door walked into, until the play screen has closed.
    private var chosen: PlazaWorld.Door?

    /// The Plaza for this player, or nil while one is already being made.
    func build(settings: AppSettings) async -> WorldDocument? {
        guard !isOpening else { return nil }
        isOpening = true
        defer { isOpening = false }
        let library = GameLibrary(source: settings.catalogueSource)
        if library.listings.isEmpty { await library.refreshIfStale() }
        // The same games the Games tab shows: a grown-up's choices first.
        let family = settings.parental.family
        var allowed = CatalogueBrowsing.visible(library.listings, hidden: settings.memory.hiddenGames).filter { family.allows(game: $0.id) }
        if settings.parental.hideScaryGames { allowed = allowed.filter { !$0.tags.contains("horror") } }
        let games = PlazaWorld.games(from: allowed, recent: settings.memory.recentGames)
        var covers: [String: Data] = [:]
        for game in games {
            if let data = await library.coverData(for: game), let small = Self.smaller(data) { covers[game.id] = small }
        }
        let plaza = PlazaWorld.build(games: games, covers: covers, playerName: settings.profile.displayName)
        doors = plaza.doors
        chosen = nil
        return plaza.world
    }

    func isDoor(_ blockID: UUID) -> Bool { doors[blockID] != nil }

    /// Walks through a door: true the first time, when the Plaza should close.
    func walkThrough(_ blockID: UUID) -> Bool {
        guard chosen == nil, let door = doors[blockID] else { return false }
        chosen = door
        return true
    }

    /// The door walked into, if any — read once, as the Plaza closes.
    func takeDoor() -> PlazaWorld.Door? {
        defer {
            chosen = nil
            doors = [:]
        }
        return chosen
    }

    /// A cover small enough to carry in a world (`WorldImage.maximumBytes`):
    /// 384 points across, as a JPEG.
    static func smaller(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 384 / image.size.width)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = small.jpegData(compressionQuality: 0.72), jpeg.count <= WorldImage.maximumBytes else { return nil }
        return jpeg
    }
}
