import SwiftUI
import AbloxCore

/// The host picks the next game, and the whole room goes there together (a
/// party, Ablox NEXT step 6). It uses the room's own "moving" message, so
/// the guests on iPads and in browsers all follow, and come straight in.
/// The browser version has the same menu item (web/src/play/hud.ts).
struct NextGameSheet: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var cloud: CloudService
    @EnvironmentObject private var bluetooth: BluetoothService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var library = GameLibrary()

    @State private var search = ""
    @State private var covers: [String: Data] = [:]
    /// The game being fetched, while it comes.
    @State private var going: String?
    @State private var problem: String?

    /// Games for more than one, that this player may see.
    private var choices: [GameListing] {
        let family = settings.parental.family
        var shown = CatalogueBrowsing.visible(library.listings, hidden: settings.memory.hiddenGames)
            .filter { family.allows(game: $0.id) && $0.maxPlayers > 1 && $0.isSupported }
        if settings.parental.hideScaryGames { shown = shown.filter { !$0.tags.contains("horror") } }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            shown = shown.filter { $0.title.lowercased().contains(query) || $0.summary.lowercased().contains(query) }
        }
        return Array(shown.prefix(80))
    }

    var body: some View {
        NavigationStack {
            List {
                if let problem {
                    Text(problem)
                        .font(.subheadline)
                        .foregroundStyle(Ablox.Palette.warning)
                }
                ForEach(choices) { listing in
                    Button {
                        Task { await go(to: listing) }
                    } label: {
                        row(listing)
                    }
                    .disabled(going != nil)
                    .task(id: listing.id) {
                        if covers[listing.id] == nil, let data = await library.coverData(for: listing) { covers[listing.id] = data }
                    }
                }
            }
            .searchable(text: $search, prompt: L("Search games"))
            .navigationTitle(L("Take everyone to another game"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
        .task {
            library.source = settings.catalogueSource
            await library.refreshIfStale()
        }
        .abloxColorScheme()
    }

    private func row(_ listing: GameListing) -> some View {
        HStack(spacing: 12) {
            CoverImage(data: covers[listing.id], title: listing.title)
                .frame(width: 92, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: listing.title).font(.headline)
                Text(L("Up to {} players", listing.maxPlayers))
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            Spacer()
            if going == listing.id {
                ProgressView()
            } else {
                DrawnIconImage(.play, size: 30)
            }
        }
        .contentShape(Rectangle())
    }

    private func go(to listing: GameListing) async {
        guard going == nil else { return }
        going = listing.id
        problem = nil
        defer { going = nil }
        guard let world = await library.worldToPlay(for: listing) else {
            if case let .failed(message) = library.status { problem = message } else { problem = L("That game could not be opened.") }
            return
        }
        // An internet room's listing points at the old listener: the next
        // room goes on the internet the same way, under its new code.
        let onInternet = cloud.isHostingRoom
        let overBluetooth = bluetooth.isHosting
        guard session.moveRoom(to: world) else {
            problem = L("Only the host can do that.")
            return
        }
        if onInternet { cloud.hostRoom(session: session) }
        if overBluetooth { bluetooth.hostRoom(session: session) }
        MenuSounds.fanfare()
        dismiss()
    }
}
