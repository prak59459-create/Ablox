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
    @EnvironmentObject private var cloud: CloudService
    @StateObject private var library = GameLibrary()

    var onEnter: (ActiveSession) -> Void

    @State private var selected: GameListing?
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var players: CatalogueShelf.PlayerCount = .any
    @State private var addingCatalogue = false
    @State private var newCatalogue = ""
    // The second round (GamesExtras.swift).
    @State private var quickFilters: Set<GameFilter> = []
    @State private var onlyNew = false
    @State private var creatingList: GameListing?
    @State private var showingLists = false
    @State private var showingHistory = false

    /// Everything the list may show: Settings → Family can keep scary games
    /// out, and the player can put games out of sight.
    private var allowed: [GameListing] {
        let family = settings.parental.family
        // A grown-up's choice of games comes first.
        let shown = CatalogueBrowsing.visible(library.listings, hidden: settings.memory.hiddenGames).filter { family.allows(game: $0.id) }
        return settings.parental.hideScaryGames ? shown.filter { !$0.tags.contains("horror") } : shown
    }

    /// "All games" in the order chosen.
    private func ordered(_ games: [GameListing]) -> [GameListing] {
        let liked = Set(settings.memory.gameNotes.filter { $0.value.liked }.map(\.key))
        let played = settings.playtime.totalSeconds
        return CatalogueBrowsing.sorted(games, by: settings.memory.gameSort,
                                        playedSeconds: { played[$0.title] ?? 0 }, liked: liked,
                                        stars: settings.memory.ratings.stars)
    }

    private var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty || tagFilter != nil || players != .any
            || !quickFilters.isEmpty || onlyNew
    }

    private var filterContext: GameFilter.Context {
        GameFilter.Context(downloaded: library.installed,
                           played: Set(settings.memory.lastPlayedAt.keys).union(settings.memory.recentGames),
                           favourites: settings.memory.favoriteGames, playLater: Set(settings.memory.playLater))
    }

    /// New or updated since last looked at.
    private func isFresh(_ listing: GameListing) -> Bool {
        CatalogueShelf.freshness(of: listing, seen: settings.memory.seenGames) != .seen
    }

    private var filtered: [GameListing] {
        // Found however it is typed: either case, full or half width,
        // hiragana or katakana (SearchText).
        let context = filterContext
        return allowed.filter { listing in
            SearchText.matches(search, in: [listing.title, listing.author, listing.summary] + listing.tags)
            && (tagFilter.map { listing.tags.contains($0) } ?? true)
            && players.allows(listing)
            && quickFilters.allSatisfy { $0.allows(listing, context) }
            && (!onlyNew || isFresh(listing))
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
                    DownloadAllCard(library: library)
                    SearchHelp(search: $search, titles: allowed.map(\.title), foundNothing: filtered.isEmpty)
                    filters
                    QuickFilterChips(selection: $quickFilters, onlyNew: $onlyNew, newCount: allowed.filter(isFresh).count)
                    if !isFiltering {
                        shelves
                        GamesExtraShelves(allowed: allowed, library: library, badges: badges(for:)) { selected = $0 }
                    }
                    HStack {
                        SectionHeader(isFiltering ? L("{} games", filtered.count) : L("All games"), systemImage: "square.grid.2x2.fill")
                        Spacer()
                        surpriseButton
                        sortMenu
                        GamesLayoutMenu(layout: $settings.memory.gamesLayout)
                    }
                    grid(ordered(filtered))
                }
            }
            .padding(Ablox.Metrics.gutter)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .onChange(of: library.status) { _, status in
            if case let .failed(message) = status { ProblemRecorder.shared.record(.catalogue, message) }
        }
        .task {
            // The cache has already been shown by the time this runs, so a
            // slow or absent network delays nothing the player can see.
            library.source = settings.catalogueSource
            await library.refreshIfStale()
        }
        .refreshable { await library.refresh() }
        .sheet(item: $selected) { listing in
            GameDetailSheet(listing: listing, library: library, onEnter: onEnter, allowed: allowed) { other in
                selected = other
            }
            .environmentObject(settings)
            .environmentObject(session)
            .environmentObject(cloud)
        }
        .sheet(item: $creatingList) { listing in
            NewListSheet(adding: listing.id).environmentObject(settings)
        }
        .sheet(isPresented: $showingLists) {
            CollectionsSheet().environmentObject(settings)
        }
        .sheet(isPresented: $showingHistory) {
            PlayHistorySheet(listings: library.listings).environmentObject(settings)
        }
        // A sheet rather than an alert: an alert's text field only types
        // with the iPad keyboard.
        .sheet(isPresented: $addingCatalogue) {
            TextPromptSheet(title: L("Add a game list"),
                            message: L("Another public GitHub repository with an index.json, like the built-in list."),
                            placeholder: L("owner/repository"), confirm: L("Add"), text: $newCatalogue) {
                let name = newCatalogue.trimmingCharacters(in: .whitespaces)
                if CatalogueSource.chosen(repository: name, branch: "main").repository == name,
                   !settings.memory.extraCatalogues.contains(name) {
                    settings.memory.extraCatalogues.append(name)
                }
                newCatalogue = ""
            }
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
                AbloxTextField(L("Search games"), text: $search, onSubmit: {
                    settings.memory.recentSearches.add(search)
                })
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ablox.Palette.inkFaint)
                    }
                    .accessibilityLabel(L("Clear"))
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Ablox.Metrics.controlRadius, style: .continuous))
            .padding(.top, 6)
            recentSearches
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
                    showingLists = true
                } label: {
                    Label(L("My lists"), systemImage: "folder")
                }
                Button {
                    showingHistory = true
                } label: {
                    Label(L("Play history"), systemImage: "clock.arrow.circlepath")
                }
                Button {
                    // Every NEW and UPDATE badge goes.
                    for listing in library.listings { settings.memory.seenGames[listing.id] = listing.revisionKey }
                } label: {
                    Label(L("Mark every game as seen"), systemImage: "checkmark.circle")
                }
            }
            Section {
                Button {
                    GameDownloads.shared.downloadAll(with: library)
                } label: {
                    Label(L("Download every game for offline"), systemImage: "arrow.down.circle")
                }
            }
        } label: {
            Label(L("Lists"), systemImage: "ellipsis.circle")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func reloadCatalogue() {
        library.source = settings.catalogueSource
        Task { await library.refresh() }
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
                let counts = Dictionary(GameShelves.tagCounts(in: allowed).map { ($0.tag, $0.count) }, uniquingKeysWith: { first, _ in first })
                ForEach(CatalogueShelf.commonTags(in: allowed), id: \.self) { tag in
                    Button {
                        tagFilter = tagFilter == tag ? nil : tag
                    } label: {
                        // How many games have it, beside the tag.
                        chip("\(tag) \(counts[tag] ?? 0)", systemImage: nil, selected: tagFilter == tag)
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
        .background(selected ? Ablox.Palette.accent.opacity(0.35) : Ablox.Palette.wash, in: Capsule())
        .foregroundStyle(Ablox.Palette.ink)
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
        badges.stars = settings.memory.ratings.stars(for: listing.id)
        badges.playLater = settings.memory.playLater.contains(listing.id)
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

    /// Big cards, small cards or a list, as chosen.
    private func grid(_ games: [GameListing]) -> some View {
        let layout = settings.memory.gamesLayout
        let columns = layout == .list ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: layout == .smallCards ? 170 : 230, maximum: layout == .smallCards ? 220 : 320), spacing: 16)]
        return LazyVGrid(columns: columns, spacing: layout == .list ? 8 : 16) {
            ForEach(games) { listing in
                Button { open(listing) } label: {
                    if layout == .list {
                        GameRowView(listing: listing, library: library, badges: badges(for: listing))
                    } else {
                        GameCard(listing: listing, library: library, badges: badges(for: listing))
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    GameOrganiseMenu(listing: listing, creatingList: Binding(
                        get: { creatingList != nil },
                        set: { creatingList = $0 ? listing : nil }))
                    Button {
                        settings.memory.hiddenGames.insert(listing.id)
                    } label: {
                        Label(L("Not interested: hide it"), systemImage: "eye.slash")
                    }
                }
            }
        }
    }

    /// Opens a game's page, keeping the search that found it.
    private func open(_ listing: GameListing) {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { settings.memory.recentSearches.add(search) }
        selected = listing
    }

    // MARK: Sorting, searching again, and a surprise

    private var sortMenu: some View {
        Menu {
            Picker(L("Order"), selection: $settings.memory.gameSort) {
                ForEach(GameSort.allCases) { order in
                    Label(order.displayName, systemImage: order.symbolName).tag(order)
                }
            }
        } label: {
            chip(settings.memory.gameSort.displayName, systemImage: "arrow.up.arrow.down", selected: settings.memory.gameSort != .suggested)
        }
        .accessibilityLabel(L("Order"))
    }

    /// A game not played yet, picked at random from what is shown.
    private var surpriseButton: some View {
        Button {
            let played = Set(settings.memory.recentGames)
            if let pick = CatalogueBrowsing.surprise(from: filtered, played: played, seed: UInt64.random(in: 0...UInt64.max)) {
                selected = pick
            }
        } label: {
            chip(L("Surprise me"), systemImage: "dice.fill", selected: false)
        }
        .buttonStyle(.plain)
        .disabled(filtered.isEmpty)
    }

    @ViewBuilder private var recentSearches: some View {
        let items = settings.memory.recentSearches.items
        if search.isEmpty, !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                    ForEach(items, id: \.self) { item in
                        Button { search = item } label: {
                            chip(item, systemImage: nil, selected: false)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                settings.memory.recentSearches.remove(item)
                            } label: {
                                Label(L("Remove"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
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
struct GameCard: View {
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
        /// The player's own stars, and whether it is waiting to be played.
        var stars = 0
        var playLater = false
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
                    HStack(spacing: 6) {
                        if badges.playLater {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Ablox.Palette.accent)
                                .accessibilityLabel(L("Play later"))
                        }
                        if badges.favourite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Ablox.Palette.warning)
                        }
                    }
                    .padding(8)
                    .shadow(radius: 2)
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
                    if badges.stars > 0 {
                        StarsLabel(stars: badges.stars)
                    }
                    if badges.timesPlayed > 0 {
                        Text(L("×{}", badges.timesPlayed))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Ablox.Palette.inkFaint)
                    }
                    DownloadSizeBadge(listing: listing, library: library)
                }
            }
            .padding(11)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Ablox.Palette.line, lineWidth: 1)
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
    /// Everything the list may show, for games like this one.
    var allowed: [GameListing] = []
    /// Opens another game's page.
    var onOpen: (GameListing) -> Void = { _ in }
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var cloud: CloudService

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

    // In pieces, each type-checked on its own: as one body this page was
    // the slowest thing in the app to compile.
    var body: some View {
        NavigationStack {
            ScrollView {
                page.padding(20)
            }
            .background(Ablox.Palette.surface)
            .navigationTitle(L("Game"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .abloxColorScheme()
        .tint(Ablox.Palette.accent)
        .task { await arrive() }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 18) {
            CoverImage(data: cover, title: listing.title)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))

            header
            shotsRow
            traitsRow

            if !listing.summary.isEmpty {
                Text(listing.summary)
                    .font(.callout)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            facts
            playRecord
            GameDetailExtras(listing: listing, library: library, allowed: allowed, onOpen: onOpen)
            howToPlay
            noteField
            tagsRow

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.danger)
            }

            actions
        }
    }

    /// The title, who made it, and the star and heart.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(listing.title)
                    .font(.title2.weight(.bold))
                Text(L("by {}", listing.displayAuthor))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            Spacer()
            Button(action: toggleFavourite) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(isFavourite ? Ablox.Palette.warning : Ablox.Palette.inkMuted)
            }
            .accessibilityLabel(isFavourite ? L("Remove from favourites") : L("Add to favourites"))
            Button(action: toggleLiked) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(isLiked ? Ablox.Palette.danger : Ablox.Palette.inkMuted)
            }
            .accessibilityLabel(isLiked ? L("Unlike") : L("Like"))
        }
    }

    @ViewBuilder private var shotsRow: some View {
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
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("My note"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            AbloxTextField(L("A few words for yourself — a tip, a password, who to play with"), text: $memo, axis: .vertical, limit: 300)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: memo) { _, text in saveMemo(text) }
        }
    }

    @ViewBuilder private var tagsRow: some View {
        if !listing.tags.isEmpty {
            HStack(spacing: 7) {
                ForEach(listing.tags, id: \.self) { tag in
                    Badge(tag, color: Ablox.Palette.accent, systemImage: "tag.fill")
                }
            }
        }
    }

    private func arrive() async {
        // Seen now: its "new" or "updated" badge can go.
        settings.memory.seenGames[listing.id] = listing.revisionKey
        settings.memory.viewedGames.viewed(listing.id)
        memo = settings.memory.gameNotes[listing.id]?.memo ?? ""
        cachedWorld = library.cachedWorld(for: listing)
        cover = await library.coverData(for: listing)
        shots = await library.shotData(for: listing)
    }

    private func toggleFavourite() {
        if isFavourite {
            settings.memory.favoriteGames.remove(listing.id)
        } else {
            settings.memory.favoriteGames.insert(listing.id)
        }
    }

    private func toggleLiked() {
        var note = settings.memory.gameNotes[listing.id] ?? GameNote()
        note.liked.toggle()
        settings.memory.gameNotes[listing.id] = note
    }

    private func saveMemo(_ text: String) {
        var note = settings.memory.gameNotes[listing.id] ?? GameNote()
        note.memo = String(text.prefix(300))
        settings.memory.gameNotes[listing.id] = note
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
            if let size = library.installedSizes[listing.id] ?? listing.downloadSize {
                fact(library.isInstalled(listing) ? L("On this iPad") : L("Size"), Megabytes.text(size))
            }
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

            GameDownloadMeterView(listing: listing)

            Button {
                askingVisibility = true
            } label: {
                Label(L("Host for friends"), systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
            .disabled(isWorking || !listing.isSupported)
            .roomVisibilityDialog(isPresented: $askingVisibility, allowsPublic: settings.parental.allowPublicRooms,
                                  allowsInternet: cloud.allowsInternetPlay) { access in
                Task { await play(hosting: true, access: access) }
            }

            if !listing.isSupported {
                Text(L("That world was made with a newer version of Ablox Studio."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            }
        }
    }

    private func play(hosting: Bool, access: RoomAccess = .routerPrivate) async {
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
        settings.memory.lastPlayed = LastPlayed(kind: .catalogue, id: listing.id, title: listing.title)
        onEnter(ActiveSession(mode: hosting ? .hosting(world, access: access) : .solo(world)))
    }
}
