import SwiftUI
import AbloxCore

// The Games tab, the second round: help while searching, quick filters,
// more shelves, a list layout, the player's own lists and stars, games to
// play later, and more on a game's page. Kept apart from DiscoverView.swift,
// which is already one of the slower files to compile. Rules in
// AbloxCore/GameShelves.swift.

// MARK: - Searching

/// Titles to finish the search with, and "Did you mean…?" when it found
/// nothing.
struct SearchHelp: View {
    @Binding var search: String
    let titles: [String]
    let foundNothing: Bool

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let suggestions = SearchText.suggestions(for: query, in: titles).filter { $0 != query }
            if foundNothing, let guess = SearchText.closest(to: query, in: titles) {
                Button {
                    search = guess
                } label: {
                    Label(L("Did you mean {}?", guess), systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ablox.Palette.accent)
            } else if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkFaint)
                        ForEach(suggestions, id: \.self) { title in
                            Button {
                                search = title
                            } label: {
                                Text(verbatim: title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Ablox.Palette.wash, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quick filters

/// Downloaded, not played, favourites, play later, gentle, not too hard —
/// and only what is new.
struct QuickFilterChips: View {
    @Binding var selection: Set<GameFilter>
    @Binding var onlyNew: Bool
    let newCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if newCount > 0 {
                    Button {
                        onlyNew.toggle()
                    } label: {
                        chip(L("New and updated ({})", newCount), "sparkles", selected: onlyNew)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(GameFilter.allCases) { filter in
                    Button {
                        if selection.contains(filter) { selection.remove(filter) } else { selection.insert(filter) }
                    } label: {
                        chip(filter.displayName, filter.symbolName, selected: selection.contains(filter))
                    }
                    .buttonStyle(.plain)
                }
                if !selection.isEmpty || onlyNew {
                    Button(L("Clear")) {
                        selection.removeAll()
                        onlyNew = false
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private func chip(_ title: String, _ symbol: String, selected: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Ablox.Palette.accent.opacity(0.35) : Ablox.Palette.wash, in: Capsule())
            .foregroundStyle(Ablox.Palette.ink)
    }
}

/// Big cards, small cards or a list.
struct GamesLayoutMenu: View {
    @Binding var layout: GamesLayout

    var body: some View {
        Menu {
            Picker(L("Layout"), selection: $layout) {
                ForEach(GamesLayout.allCases, id: \.self) { choice in
                    Label(choice.displayName, systemImage: choice.symbolName).tag(choice)
                }
            }
        } label: {
            Image(systemName: layout.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Ablox.Palette.wash, in: Capsule())
                .foregroundStyle(Ablox.Palette.ink)
        }
        .accessibilityLabel(L("Layout"))
    }
}

// MARK: - A game as a row

/// A game in the list layout: a small cover, its name and what is known.
struct GameRowView: View {
    let listing: GameListing
    @ObservedObject var library: GameLibrary
    let badges: GameCard.Badges
    @State private var cover: Data?

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(data: cover, title: listing.title)
                .frame(width: 88, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(listing.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    if let fresh = badges.fresh {
                        Text(fresh)
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Ablox.Palette.danger, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text(listing.summary.isEmpty ? listing.displayAuthor : listing.summary)
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
            if badges.stars > 0 { StarsLabel(stars: badges.stars) }
            if badges.playLater {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Ablox.Palette.accent)
                    .accessibilityLabel(L("Play later"))
            }
            if library.isInstalled(listing) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Ablox.Palette.success)
                    .accessibilityLabel(L("Downloaded"))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: listing.id) {
            cover = await library.coverData(for: listing)
        }
    }
}

/// "★ 4", small.
struct StarsLabel: View {
    let stars: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
            Text("\(stars)")
        }
        .font(.caption2.weight(.bold).monospacedDigit())
        .foregroundStyle(Ablox.Palette.warning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("{} stars", stars))
    }
}

// MARK: - More shelves

/// This week's pick, play later, the player's lists, like one they liked,
/// not played yet, updated since, quick to load, better together, looked at
/// lately.
struct GamesExtraShelves: View {
    @EnvironmentObject private var settings: AppSettings
    let allowed: [GameListing]
    @ObservedObject var library: GameLibrary
    let badges: (GameListing) -> GameCard.Badges
    let onSelect: (GameListing) -> Void

    private var played: Set<String> {
        Set(settings.memory.lastPlayedAt.keys).union(settings.memory.recentGames)
    }

    private func pick(_ ids: [String]) -> [GameListing] {
        ids.compactMap { id in allowed.first { $0.id == id } }
    }

    var body: some View {
        if let weekly = GameShelves.weeklyPick(from: allowed) {
            shelf(L("This week's pick"), "calendar", [weekly])
        }
        let later = pick(settings.memory.playLater)
        if !later.isEmpty { shelf(L("Play later"), "bookmark.fill", later) }
        ForEach(settings.memory.collections.all) { collection in
            let games = pick(collection.games)
            if !games.isEmpty { shelf(collection.name, "folder.fill", games) }
        }
        let liked = settings.memory.gameNotes.filter { $0.value.liked }.map(\.key).sorted()
            + Array(settings.memory.favoriteGames).sorted()
        if let because = GameShelves.becauseYouLiked(allowed, likedInOrder: liked, played: played) {
            shelf(L("Because you liked {}", because.source.title), "heart.fill", because.games)
        }
        let fresh = GameShelves.notPlayed(allowed, played: played)
        if !fresh.isEmpty { shelf(L("Not played yet"), "sparkle", fresh) }
        let updated = GameShelves.updatedSincePlayed(allowed, lastPlayed: settings.memory.lastPlayedAt)
        if !updated.isEmpty { shelf(L("Updated since you played"), "arrow.triangle.2.circlepath", updated) }
        let quick = GameShelves.quickToLoad(allowed)
        if quick.count >= 3 { shelf(L("Quick to load"), "bolt.fill", quick) }
        let together = GameShelves.betterTogether(allowed)
        if !together.isEmpty { shelf(L("Better together"), "person.3.fill", together) }
        let viewed = pick(settings.memory.viewedGames.games).filter { !played.contains($0.id) }
        if !viewed.isEmpty { shelf(L("Looked at lately"), "eye.fill", viewed) }
    }

    private func shelf(_ title: String, _ symbol: String, _ games: [GameListing]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, systemImage: symbol)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(games) { listing in
                        Button { onSelect(listing) } label: {
                            GameCard(listing: listing, library: library, badges: badges(listing))
                                .frame(width: 240)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - A game's menu

/// Play later, the player's lists and stars, for a card's long press and
/// the game page.
struct GameOrganiseMenu: View {
    @EnvironmentObject private var settings: AppSettings
    let listing: GameListing
    @Binding var creatingList: Bool

    var body: some View {
        let later = settings.memory.playLater.contains(listing.id)
        Button {
            settings.memory.togglePlayLater(listing.id)
        } label: {
            Label(later ? L("Remove from Play later") : L("Play later"), systemImage: later ? "bookmark.slash" : "bookmark")
        }
        Menu {
            ForEach(settings.memory.collections.all) { collection in
                let inside = settings.memory.collections.contains(listing.id, in: collection.id)
                Button {
                    settings.memory.collections.toggle(listing.id, in: collection.id)
                } label: {
                    Label(collection.name, systemImage: inside ? "checkmark" : "folder")
                }
            }
            Button {
                creatingList = true
            } label: {
                Label(L("New list…"), systemImage: "folder.badge.plus")
            }
        } label: {
            Label(L("Add to a list"), systemImage: "folder")
        }
        Menu {
            ForEach(1...5, id: \.self) { stars in
                Button {
                    settings.memory.ratings.rate(listing.id, stars)
                } label: {
                    Label(String(repeating: "★", count: stars),
                          systemImage: settings.memory.ratings.stars(for: listing.id) == stars ? "checkmark" : "star")
                }
            }
        } label: {
            Label(L("My stars"), systemImage: "star")
        }
    }
}

// MARK: - More on a game's page

/// Stars, play later, lists, best score, last played, games like it and by
/// the same maker, and removing the download.
struct GameDetailExtras: View {
    @EnvironmentObject private var settings: AppSettings
    let listing: GameListing
    @ObservedObject var library: GameLibrary
    let allowed: [GameListing]
    let onOpen: (GameListing) -> Void

    @State private var creatingList = false
    @State private var reported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            starsRow
            organiseRow
            record
            GamePicturesRow(game: listing.title)
            related(L("Games like this"), GameShelves.similar(to: listing, in: allowed))
            related(L("More by {}", listing.displayAuthor), GameShelves.byAuthor(of: listing, in: allowed))
            tools
        }
        .sheet(isPresented: $creatingList) {
            NewListSheet(adding: listing.id)
        }
    }

    private var starsRow: some View {
        let stars = settings.memory.ratings.stars(for: listing.id)
        return HStack(spacing: 6) {
            Text(L("My stars"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            ForEach(1...5, id: \.self) { value in
                Button {
                    settings.memory.ratings.rate(listing.id, value)
                } label: {
                    Image(systemName: value <= stars ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(value <= stars ? Ablox.Palette.warning : Ablox.Palette.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("{} stars", value))
                .accessibilityAddTraits(value == stars ? .isSelected : [])
            }
        }
    }

    private var organiseRow: some View {
        let later = settings.memory.playLater.contains(listing.id)
        let lists = settings.memory.collections.all.filter { $0.games.contains(listing.id) }.map(\.name)
        return HStack(spacing: 10) {
            Button {
                settings.memory.togglePlayLater(listing.id)
            } label: {
                Label(later ? L("In Play later") : L("Play later"), systemImage: later ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(NeonButtonStyle(.secondary))
            Menu {
                GameOrganiseMenu(listing: listing, creatingList: $creatingList)
            } label: {
                Label(lists.isEmpty ? L("Add to a list") : lists.joined(separator: ", "), systemImage: "folder")
                    .lineLimit(1)
            }
            .buttonStyle(NeonButtonStyle(.secondary))
            ShareLink(item: L("Let's play {} in Ablox!", listing.title)) {
                Label(L("Share"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NeonButtonStyle(.secondary))
        }
    }

    @ViewBuilder private var record: some View {
        let best = settings.memory.bestScores[listing.title] ?? 0
        let last = settings.memory.lastPlayedAt[listing.id]
        if best > 0 || last != nil {
            HStack(spacing: 16) {
                if best > 0 {
                    Label(L("Best score {}", best), systemImage: "trophy.fill")
                        .foregroundStyle(Ablox.Palette.warning)
                }
                if let last {
                    Label(L("Last played {}", last.formatted(.relative(presentation: .named))), systemImage: "calendar")
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder private func related(_ title: String, _ games: [GameListing]) -> some View {
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(games) { other in
                            Button { onOpen(other) } label: {
                                GameCard(listing: other, library: library)
                                    .frame(width: 180)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var tools: some View {
        HStack(spacing: 10) {
            if library.isInstalled(listing) {
                Button(role: .destructive) {
                    library.removeDownload(listing)
                } label: {
                    Label(L("Remove the download"), systemImage: "trash")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
            Button {
                ProblemRecorder.shared.record(.catalogue, L("A player reported a problem with this game."), detail: listing.title)
                reported = true
            } label: {
                Label(reported ? L("Noted — thank you") : L("Something wrong with this game?"),
                      systemImage: reported ? "checkmark" : "exclamationmark.bubble")
            }
            .buttonStyle(NeonButtonStyle(.secondary))
            .disabled(reported)
        }
    }
}

// MARK: - Lists

/// A new list, and the game it was made for put in it.
struct NewListSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    var adding: String?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("A new list"), systemImage: "folder.badge.plus")
                .font(.headline)
            Text(L("Like: Racing, With Grandma, Scary ones."))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
            AbloxTextField(L("Name"), text: $name, limit: GameCollections.maximumNameLength, onSubmit: create)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if settings.memory.collections.all.count >= GameCollections.maximumCollections {
                Text(L("You have {} lists, the most there can be.", GameCollections.maximumCollections))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            }
            HStack {
                Button(L("Cancel")) { dismiss() }
                    .buttonStyle(NeonButtonStyle(.secondary))
                Spacer()
                Button(L("Make it"), action: create)
                    .buttonStyle(NeonButtonStyle(.primary))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .presentationDetents([.height(280)])
        .abloxColorScheme()
    }

    private func create() {
        guard let id = settings.memory.collections.create(name) else { return }
        if let adding { settings.memory.collections.toggle(adding, in: id) }
        dismiss()
    }
}

/// The player's lists: rename and delete.
struct CollectionsSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var renaming: GameCollections.Collection?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if settings.memory.collections.all.isEmpty {
                    Text(L("No lists yet. Long-press a game and choose Add to a list."))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(settings.memory.collections.all) { collection in
                    HStack {
                        Label(collection.name, systemImage: "folder.fill")
                        Spacer()
                        Text(L("{} games", collection.games.count))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            settings.memory.collections.delete(collection.id)
                        } label: {
                            Label(L("Delete"), systemImage: "trash")
                        }
                        Button {
                            newName = collection.name
                            renaming = collection
                        } label: {
                            Label(L("Rename"), systemImage: "pencil")
                        }
                        .tint(Ablox.Palette.accent)
                    }
                }
            }
            .navigationTitle(L("My lists"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label(L("New list…"), systemImage: "plus")
                    }
                }
            }
        }
        .abloxColorScheme()
        .sheet(isPresented: $creating) { NewListSheet() }
        .sheet(item: $renaming) { collection in
            TextPromptSheet(title: L("Rename"), message: L("A new name for this list."), placeholder: L("Name"),
                            confirm: L("Rename"), text: $newName) {
                settings.memory.collections.rename(collection.id, to: newName)
            }
        }
    }
}

// MARK: - What was played

/// Every game played on this iPad: how often, how long, when last, the
/// best score.
struct PlayHistorySheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let listings: [GameListing]

    private struct Row: Identifiable {
        let id: String
        let title: String
        let times: Int
        let minutes: Int
        let last: Date?
        let best: Int
    }

    private var rows: [Row] {
        let log = settings.playtime
        let byTitle = Dictionary(listings.map { ($0.title, $0.id) }, uniquingKeysWith: { first, _ in first })
        return log.timesPlayed.keys.map { title in
            let id = byTitle[title]
            return Row(id: title, title: title, times: log.timesPlayed[title] ?? 0,
                       minutes: Int((log.totalSeconds[title] ?? 0) / 60),
                       last: id.flatMap { settings.memory.lastPlayedAt[$0] },
                       best: settings.memory.bestScores[title] ?? 0)
        }
        .sorted { ($0.last ?? .distantPast, $0.times) > ($1.last ?? .distantPast, $1.times) }
    }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    Text(L("Nothing played yet."))
                        .foregroundStyle(Ablox.Palette.inkMuted)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: row.title)
                            .font(.headline)
                        Text(L("Played {} times, {} minutes in all", row.times, row.minutes))
                            .font(.caption)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                        HStack(spacing: 12) {
                            if let last = row.last {
                                Label(last.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            }
                            if row.best > 0 {
                                Label(L("Best score {}", row.best), systemImage: "trophy.fill")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                    }
                }
            }
            .navigationTitle(L("Play history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .abloxColorScheme()
    }
}
