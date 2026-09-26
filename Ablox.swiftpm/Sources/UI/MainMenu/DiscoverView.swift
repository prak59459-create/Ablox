import SwiftUI

/// Worlds other people have published, browsed as a grid of cover pictures.
///
/// There is no server behind this. The list is `index.json` in a public GitHub
/// repository, and a game is a world file next to it — see `GameCatalogue`.
/// That is why publishing is a pull request rather than an upload button, and
/// why this screen only ever reads.
struct DiscoverView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var library = GameLibrary()

    var onEnter: (ActiveSession) -> Void

    @State private var selected: GameListing?
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var players: CatalogueShelf.PlayerCount = .any
    @State private var downloading: (done: Int, total: Int)?
    @State private var addingCatalogue = false
    @State private var newCatalogue = ""

    /// Everything the list may show: Settings → Family can keep scary games out.
    private var allowed: [GameListing] {
        settings.parental.hideScaryGames
            ? library.listings.filter { !$0.tags.contains("horror") }
            : library.listings
    }

    private var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty || tagFilter != nil || players != .any
    }

    private var filtered: [GameListing] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return allowed.filter { listing in
            (query.isEmpty
                || listing.title.lowercased().contains(query)
                || listing.author.lowercased().contains(query)
                || listing.tags.contains { $0.lowercased().contains(query) })
            && (tagFilter.map { listing.tags.contains($0) } ?? true)
            && players.allows(listing)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statusBanner

                if library.listings.isEmpty {
                    emptyState
                } else {
                    filters
                    if !isFiltering { shelves }
                    SectionHeader(isFiltering ? L("{} games", filtered.count) : L("All games"), systemImage: "square.grid.2x2.fill")
                    grid(filtered)
                }
            }
            .padding(Ablox.Metrics.gutter)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .task {
            // The cache has already been shown by the time this runs, so a
            // slow or absent network delays nothing the player can see.
            library.source = settings.catalogueSource
            await library.refresh()
        }
        .refreshable { await library.refresh() }
        .sheet(item: $selected) { listing in
            GameDetailSheet(listing: listing, library: library, onEnter: onEnter)
                .environmentObject(settings)
                .environmentObject(session)
        }
        .alert(L("Add a game list"), isPresented: $addingCatalogue) {
            TextField(L("owner/repository"), text: $newCatalogue)
            Button(L("Add")) {
                let name = newCatalogue.trimmingCharacters(in: .whitespaces)
                if CatalogueSource.chosen(repository: name, branch: "main").repository == name,
                   !settings.memory.extraCatalogues.contains(name) {
                    settings.memory.extraCatalogues.append(name)
                }
                newCatalogue = ""
            }
            Button(L("Cancel"), role: .cancel) { newCatalogue = "" }
        } message: {
            Text(L("Another public GitHub repository with an index.json, like the built-in list."))
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Games"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Spacer()
                catalogueMenu
            }
            Text(L("Worlds people have published. Download one and play it on your own, or host it for friends."))
                .font(.subheadline)
                .foregroundStyle(Ablox.Palette.inkMuted)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Ablox.Palette.inkFaint)
                TextField(L("Search games"), text: $search)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Ablox.Metrics.controlRadius, style: .continuous))
            .padding(.top, 6)
        }
    }

    /// Which list, more lists, and keeping them all for offline.
    private var catalogueMenu: some View {
        Menu {
            Section(L("Game lists")) {
                Button {
                    settings.catalogueRepository = CatalogueSource.default.repository
                    reloadCatalogue()
                } label: {
                    Label(L("The built-in list"), systemImage: settings.catalogueRepository == CatalogueSource.default.repository ? "checkmark" : "list.bullet")
                }
                ForEach(settings.memory.extraCatalogues, id: \.self) { repository in
                    Button {
                        settings.catalogueRepository = repository
                        reloadCatalogue()
                    } label: {
                        Label(repository, systemImage: settings.catalogueRepository == repository ? "checkmark" : "list.bullet")
                    }
                }
                Button {
                    addingCatalogue = true
                } label: {
                    Label(L("Add a game list…"), systemImage: "plus")
                }
            }
            Section {
                Button {
                    Task { await downloadEverything() }
                } label: {
                    Label(L("Download every game for offline"), systemImage: "arrow.down.circle")
                }
            }
        } label: {
            if let downloading {
                Label(L("{} of {}", downloading.done, downloading.total), systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
            } else {
                Label(L("Lists"), systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func reloadCatalogue() {
        library.source = settings.catalogueSource
        Task { await library.refresh() }
    }

    private func downloadEverything() async {
        downloading = (0, 0)
        await library.downloadAll { done, total in
            Task { @MainActor in downloading = (done, total) }
        }
        downloading = nil
    }

    /// Kinds of game, and how many people.
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(CatalogueShelf.PlayerCount.allCases, id: \.self) { option in
                        Button(option.displayName) { players = option }
                    }
                } label: {
                    chip(players.displayName, systemImage: "person.2.fill", selected: players != .any)
                }
                ForEach(CatalogueShelf.commonTags(in: allowed), id: \.self) { tag in
                    Button {
                        tagFilter = tagFilter == tag ? nil : tag
                    } label: {
                        chip(tag, systemImage: nil, selected: tagFilter == tag)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(_ title: String, systemImage: String?, selected: Bool) -> some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(verbatim: title)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? Ablox.Palette.accent.opacity(0.35) : Color.white.opacity(0.07), in: Capsule())
        .foregroundStyle(.white)
    }

    /// Today's pick, favourites, recently played, nearby, and your own.
    @ViewBuilder private var shelves: some View {
        if let pick = CatalogueShelf.dailyPick(from: allowed) {
            Button { selected = pick } label: {
                HStack(spacing: 16) {
                    GameCard(listing: pick, library: library, badges: badges(for: pick))
                        .frame(width: 280)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("Today's pick"), systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(Ablox.Palette.warning)
                        Text(pick.summary)
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .lineLimit(4)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        let favourites = allowed.filter { settings.memory.favoriteGames.contains($0.id) }
        if !favourites.isEmpty { shelf(L("Favourites"), "star.fill", favourites) }
        let recent = settings.memory.recentGames.compactMap { id in allowed.first { $0.id == id } }
        if !recent.isEmpty { shelf(L("Played recently"), "clock.arrow.circlepath", recent) }
        let nearby = allowed.filter { listing in session.discoveredPeers.contains { $0.worldName == listing.title && $0.isCompatible } }
        if !nearby.isEmpty { shelf(L("Being played nearby"), "antenna.radiowaves.left.and.right", nearby) }
        if !store.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(L("My games"), systemImage: "hammer.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.entries.prefix(12)) { entry in
                            Button {
                                if let world = store.load(entry) { onEnter(ActiveSession(mode: .solo(world))) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    WorldThumbnail(store: store, id: entry.id, name: entry.name)
                                        .frame(width: 180, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text(entry.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .frame(width: 180)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func shelf(_ title: String, _ symbol: String, _ games: [GameListing]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, systemImage: symbol)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(games) { listing in
                        Button { selected = listing } label: {
                            GameCard(listing: listing, library: library, badges: badges(for: listing))
                                .frame(width: 240)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// What the card says about a game: new, updated, liked, played.
    private func badges(for listing: GameListing) -> GameCard.Badges {
        var badges = GameCard.Badges()
        switch CatalogueShelf.freshness(of: listing, seen: settings.memory.seenGames) {
        case .new: badges.fresh = L("NEW")
        case .updated: badges.fresh = L("UPDATE")
        case .seen: break
        }
        badges.favourite = settings.memory.favoriteGames.contains(listing.id)
        badges.traits = CatalogueShelf.traits(of: listing)
        badges.timesPlayed = settings.playtime.timesPlayed[listing.title] ?? 0
        badges.nearby = session.discoveredPeers.contains { $0.worldName == listing.title && $0.isCompatible }
        return badges
    }

    @ViewBuilder private var statusBanner: some View {
        switch library.status {
        case .idle:
            EmptyView()
        case .refreshing:
            banner(L("Checking for new games…"), symbol: "arrow.triangle.2.circlepath", colour: Ablox.Palette.inkMuted)
        case let .offline(message):
            // Not an error. An iPad in a classroom is offline more often than
            // not, and the cached list is still perfectly playable.
            banner(message, symbol: "wifi.slash", colour: Ablox.Palette.warning)
        case let .failed(message):
            banner(message, symbol: "exclamationmark.triangle.fill", colour: Ablox.Palette.danger)
        }
    }

    private func banner(_ message: String, symbol: String, colour: Color) -> some View {
        Label(message, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(colour)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyState: some View {
        EmptyStateView(
            title: L("No games yet"),
            message: L("Games appear here once someone publishes one. Ablox Studio can prepare yours."),
            systemImage: "square.stack.3d.up.slash"
        )
    }

    private func grid(_ games: [GameListing]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)],
            spacing: 16
        ) {
            ForEach(games) { listing in
                Button { selected = listing } label: {
                    GameCard(listing: listing, library: library, badges: badges(for: listing))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A saved world's picture, taken while it was played, or a placeholder.
struct WorldThumbnail: View {
    let store: ProjectStore
    let id: UUID
    let name: String

    var body: some View {
        if let data = store.thumbnail(for: id), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            CoverImage(data: nil, title: name)
        }
    }
}

// MARK: - Card

/// One cover picture with its title underneath.
private struct GameCard: View {
    let listing: GameListing
    @ObservedObject var library: GameLibrary
    var badges = Badges()

    /// What the menu knows about this game beyond the listing.
    struct Badges {
        var fresh: String?
        var favourite = false
        var traits = CatalogueShelf.Traits()
        var timesPlayed = 0
        var nearby = false
    }

    @State private var cover: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(data: cover, title: listing.title)
                .frame(height: 128)
                .clipped()
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        if let fresh = badges.fresh {
                            Text(fresh)
                                .font(.system(size: 10, weight: .black))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Ablox.Palette.danger, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        if badges.nearby {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                                .padding(5)
                                .background(Ablox.Palette.success, in: Circle())
                                .foregroundStyle(.white)
                                .accessibilityLabel(L("Being played nearby"))
                        }
                    }
                    .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if badges.favourite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Ablox.Palette.warning)
                            .padding(8)
                            .shadow(radius: 2)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(listing.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Ablox.Palette.ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(listing.displayAuthor)
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.inkMuted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if badges.traits.scary {
                        Image(systemName: "moon.fill")
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.magenta)
                            .accessibilityLabel(L("Scary"))
                    }
                    if badges.traits.hard {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.warning)
                            .accessibilityLabel(L("Hard"))
                    }
                    if badges.traits.gentle {
                        Image(systemName: "leaf.fill")
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.success)
                            .accessibilityLabel(L("Gentle"))
                    }
                    if badges.timesPlayed > 0 {
                        Text(L("×{}", badges.timesPlayed))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Ablox.Palette.inkFaint)
                    }
                    if library.isInstalled(listing) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.success)
                            .accessibilityLabel(L("Downloaded"))
                    }
                }
            }
            .padding(11)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .task(id: listing.id) {
            cover = await library.coverData(for: listing)
        }
    }
}

/// A cover picture, or a generated stand-in when there is none.
///
/// The stand-in is derived from the title rather than random, so the same game
/// always looks the same — a list that reshuffles its own colours on every
/// scroll is worse than one with no pictures at all.
struct CoverImage: View {
    let data: Data?
    let title: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: placeholderColours,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Text(initials)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var initials: String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var placeholderColours: [Color] {
        // The same stable hash the avatar generator uses, so this is
        // deterministic across launches and across devices.
        let palette = ColorRGBA.palette
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(title.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3
        }
        let first = palette[Int(hash % UInt64(palette.count))]
        let second = palette[Int((hash >> 17) % UInt64(palette.count))]
        return [Color(first), Color(second)]
    }
}

// MARK: - Detail

/// What a game is, and the button that downloads it.
private struct GameDetailSheet: View {
    let listing: GameListing
    @ObservedObject var library: GameLibrary
    var onEnter: (ActiveSession) -> Void
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var cover: Data?
    @State private var shots: [Data] = []
    @State private var memo = ""
    @State private var isWorking = false
    @State private var problem: String?
    @State private var askingVisibility = false
    /// The copy on this iPad, read once when the page opens — the page is
    /// redrawn on every keystroke of the note, and a world is not small.
    @State private var cachedWorld: WorldDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CoverImage(data: cover, title: listing.title)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(listing.title)
                                .font(.title2.weight(.bold))
                            Text(L("by {}", listing.displayAuthor))
                                .font(.subheadline)
                                .foregroundStyle(Ablox.Palette.inkMuted)
                        }
                        Spacer()
                        Button {
                            if isFavourite { settings.memory.favoriteGames.remove(listing.id) } else { settings.memory.favoriteGames.insert(listing.id) }
                        } label: {
                            Image(systemName: isFavourite ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(isFavourite ? Ablox.Palette.warning : Ablox.Palette.inkMuted)
                        }
                        .accessibilityLabel(isFavourite ? L("Remove from favourites") : L("Add to favourites"))
                        Button {
                            var note = settings.memory.gameNotes[listing.id] ?? GameNote()
                            note.liked.toggle()
                            settings.memory.gameNotes[listing.id] = note
                        } label: {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundStyle(isLiked ? Ablox.Palette.danger : Ablox.Palette.inkMuted)
                        }
                        .accessibilityLabel(isLiked ? L("Unlike") : L("Like"))
                    }

                    if !shots.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(shots.indices, id: \.self) { index in
                                    CoverImage(data: shots[index], title: listing.title)
                                        .frame(width: 220, height: 124)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    traitsRow

                    if !listing.summary.isEmpty {
                        Text(listing.summary)
                            .font(.callout)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    facts

                    playRecord

                    howToPlay

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("My note"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ablox.Palette.inkMuted)
                        TextField(L("A few words for yourself — a tip, a password, who to play with"), text: $memo, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onChange(of: memo) { _, text in
                                var note = settings.memory.gameNotes[listing.id] ?? GameNote()
                                note.memo = String(text.prefix(300))
                                settings.memory.gameNotes[listing.id] = note
                            }
                    }

                    if !listing.tags.isEmpty {
                        HStack(spacing: 7) {
                            ForEach(listing.tags, id: \.self) { tag in
                                Badge(tag, color: Ablox.Palette.accent, systemImage: "tag.fill")
                            }
                        }
                    }

                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.danger)
                    }

                    actions
                }
                .padding(20)
            }
            .background(Color(red: 0.05, green: 0.06, blue: 0.11))
            .navigationTitle(L("Game"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Ablox.Palette.accent)
        .task {
            // Seen now: its "new" or "updated" badge can go.
            settings.memory.seenGames[listing.id] = listing.revisionKey
            memo = settings.memory.gameNotes[listing.id]?.memo ?? ""
            cachedWorld = library.cachedWorld(for: listing)
            cover = await library.coverData(for: listing)
            shots = await library.shotData(for: listing)
        }
    }

    private var isFavourite: Bool { settings.memory.favoriteGames.contains(listing.id) }
    private var isLiked: Bool { settings.memory.gameNotes[listing.id]?.liked ?? false }

    /// Scary, hard, gentle, together — from the game's tags.
    @ViewBuilder private var traitsRow: some View {
        let traits = CatalogueShelf.traits(of: listing)
        HStack(spacing: 8) {
            if traits.scary { Badge(L("Scary"), color: Ablox.Palette.magenta, systemImage: "moon.fill") }
            if traits.hard { Badge(L("Hard"), color: Ablox.Palette.warning, systemImage: "flame.fill") }
            if traits.gentle { Badge(L("Gentle"), color: Ablox.Palette.success, systemImage: "leaf.fill") }
            if traits.social { Badge(L("Better together"), color: Ablox.Palette.accent, systemImage: "person.3.fill") }
        }
    }

    /// How much this iPad has played it.
    @ViewBuilder private var playRecord: some View {
        let times = settings.playtime.timesPlayed[listing.title] ?? 0
        let minutes = Int((settings.playtime.totalSeconds[listing.title] ?? 0) / 60)
        if times > 0 {
            Label(L("Played {} times, {} minutes in all", times, minutes), systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
        }
    }

    /// The game's own how-to and quests, read from its scripts once it is
    /// on this iPad.
    @ViewBuilder private var howToPlay: some View {
        let sources = (cachedWorld?.scripts ?? []).map(\.source)
        let lines = CatalogueShelf.instructions(inScripts: sources)
        let quests = CatalogueShelf.quests(inScripts: sources)
        if !lines.isEmpty || !quests.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !lines.isEmpty {
                    Text(L("How to play"))
                        .font(.headline)
                    ForEach(lines.indices, id: \.self) { index in
                        Text(verbatim: lines[index])
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !quests.isEmpty {
                    Text(L("Quests ({})", quests.count))
                        .font(.headline)
                        .padding(.top, 4)
                    ForEach(quests.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundStyle(Ablox.Palette.accent)
                            Text(verbatim: quests[index].title)
                                .font(.subheadline)
                            Spacer()
                            Text(L("+{}", quests[index].reward))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Ablox.Palette.warning)
                        }
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Which of three save slots this game plays with.
    @ViewBuilder private var saveSlotPicker: some View {
        if let world = cachedWorld, world.hasScript {
            Picker(L("Save slot"), selection: Binding(
                get: { settings.memory.saveSlots[world.id.uuidString] ?? 1 },
                set: { settings.memory.saveSlots[world.id.uuidString] = $0 }
            )) {
                ForEach(1...SaveSlots.count, id: \.self) { slot in
                    Text(L("Slot {}", slot)).tag(slot)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// A room for this game, open nearby.
    private var nearbyRoom: DiscoveredPeer? {
        session.discoveredPeers.first { $0.worldName == listing.title && $0.isCompatible && !$0.isFull }
    }

    private var facts: some View {
        HStack(spacing: 18) {
            fact(L("Parts"), "\(listing.blockCount)")
            fact(L("Players"), "\(listing.maxPlayers)")
            fact(L("Updated"), listing.updatedAt.formatted(date: .abbreviated, time: .omitted))
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Ablox.Palette.inkFaint)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Ablox.Palette.ink)
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 9) {
            saveSlotPicker

            if let room = nearbyRoom {
                if let code = room.publicCode {
                    Button {
                        dismiss()
                        settings.memory.played(listing.id)
                        onEnter(ActiveSession(mode: .joining(room, code: code)))
                    } label: {
                        Label(L("Join {}'s room nearby", room.hostName), systemImage: "person.2.wave.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonButtonStyle(.primary, fullWidth: true))
                } else {
                    Label(L("{} is playing this nearby — ask them for the room code in the Play tab.", room.hostName),
                          systemImage: "person.2.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.accent)
                }
            }

            Button {
                Task { await play(hosting: false) }
            } label: {
                Label(
                    library.isInstalled(listing) ? L("Play") : L("Download and play"),
                    systemImage: library.isInstalled(listing) ? "play.fill" : "arrow.down.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonButtonStyle(.primary, fullWidth: true))
            .disabled(isWorking || !listing.isSupported)

            Button {
                askingVisibility = true
            } label: {
                Label(L("Host for friends"), systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
            .disabled(isWorking || !listing.isSupported)
            .roomVisibilityDialog(isPresented: $askingVisibility, allowsPublic: settings.parental.allowPublicRooms) { isPublic in
                Task { await play(hosting: true, isPublic: isPublic) }
            }

            if !listing.isSupported {
                Text(L("That world was made with a newer version of Ablox Studio."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            }
        }
    }

    private func play(hosting: Bool, isPublic: Bool = false) async {
        isWorking = true
        defer { isWorking = false }
        problem = nil

        // The cached copy when there is one, so a second play costs nothing
        // and works with no network at all.
        // (`??` runs its right side in a closure that cannot `await`, so
        // the download is a separate step.)
        var found = library.cachedWorld(for: listing)
        if found == nil {
            found = await library.download(listing)
        }
        guard let world = found else {
            if case let .failed(message) = library.status { problem = message }
            return
        }

        // A stale block count is worth saying out loud but is not a reason to
        // refuse: the world itself decoded, and it is the world that matters.
        if let mismatch = listing.mismatch(with: world) {
            problem = mismatch
        }

        dismiss()
        settings.memory.played(listing.id)
        onEnter(ActiveSession(mode: hosting ? .hosting(world, isPublic: isPublic) : .solo(world)))
    }
}
