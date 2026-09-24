import SwiftUI

/// Worlds other people have published, browsed as a grid of cover pictures.
///
/// There is no server behind this. The list is `index.json` in a public GitHub
/// repository, and a game is a world file next to it — see `GameCatalogue`.
/// That is why publishing is a pull request rather than an upload button, and
/// why this screen only ever reads.
struct DiscoverView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var library = GameLibrary()

    var onEnter: (ActiveSession) -> Void

    @State private var selected: GameListing?
    @State private var search = ""

    private var filtered: [GameListing] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return library.listings }
        return library.listings.filter { listing in
            listing.title.lowercased().contains(query)
                || listing.author.lowercased().contains(query)
                || listing.tags.contains { $0.lowercased().contains(query) }
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
                    grid
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
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("Games"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
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

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)],
            spacing: 16
        ) {
            ForEach(filtered) { listing in
                Button { selected = listing } label: {
                    GameCard(listing: listing, library: library)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Card

/// One cover picture with its title underneath.
private struct GameCard: View {
    let listing: GameListing
    @ObservedObject var library: GameLibrary

    @State private var cover: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(data: cover, title: listing.title)
                .frame(height: 128)
                .clipped()

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

    @Environment(\.dismiss) private var dismiss
    @State private var cover: Data?
    @State private var isWorking = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CoverImage(data: cover, title: listing.title)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: Ablox.Metrics.cardRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(listing.title)
                            .font(.title2.weight(.bold))
                        Text(L("by {}", listing.displayAuthor))
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                    }

                    if !listing.summary.isEmpty {
                        Text(listing.summary)
                            .font(.callout)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    facts

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
        .task { cover = await library.coverData(for: listing) }
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
                Task { await play(hosting: true) }
            } label: {
                Label(L("Host for friends"), systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonButtonStyle(.secondary, fullWidth: true))
            .disabled(isWorking || !listing.isSupported)

            if !listing.isSupported {
                Text(L("That world was made with a newer version of Ablox Studio."))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            }
        }
    }

    private func play(hosting: Bool) async {
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
        onEnter(ActiveSession(mode: hosting ? .hosting(world) : .solo(world)))
    }
}
