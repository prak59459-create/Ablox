import SwiftUI

/// Badges, the title to wear, a player's records across every game, and the
/// album of pictures and clips.
struct ProfileSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable, Identifiable {
        case badges, records, album
        var id: String { rawValue }
        var title: String {
            switch self {
            case .badges: return L("Badges")
            case .records: return L("Records")
            case .album: return L("Album")
            }
        }
    }

    @State private var tab: Tab = .badges
    @State private var pictures: [URL] = []
    @State private var sharing: SharedFile?

    private var stats: ProgressStats {
        settings.progressStats(worldsMade: store.entries.count, pictures: pictures.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker(L("Profile"), selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                ScrollView {
                    switch tab {
                    case .badges: badges
                    case .records: records
                    case .album: album
                    }
                }
            }
            .padding(.top, 12)
            .background(Color(red: 0.05, green: 0.06, blue: 0.11))
            .navigationTitle(settings.profile.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Ablox.Palette.accent)
        .onAppear { pictures = ScreenshotStore.all() }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
    }

    // MARK: Badges

    private var badges: some View {
        let earned = Set(Achievement.earned(stats))
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Title under your name"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ablox.Palette.inkMuted)
                Picker(L("Title"), selection: $settings.profile.title) {
                    Text(L("None")).tag("")
                    ForEach(Achievement.allCases.filter { earned.contains($0) }) { badge in
                        Text(badge.title).tag(badge.title)
                    }
                }
                .pickerStyle(.menu)
            }
            Text(L("{} of {} badges", earned.count, Achievement.allCases.count))
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(Achievement.allCases) { badge in
                    let has = earned.contains(badge)
                    VStack(spacing: 7) {
                        Image(systemName: badge.symbolName)
                            .font(.title)
                            .foregroundStyle(has ? Ablox.Palette.warning : Ablox.Palette.inkFaint)
                        Text(badge.title)
                            .font(.subheadline.weight(.bold))
                        Text(badge.detail)
                            .font(.caption2)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(has ? 1 : 0.45)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(has ? L("Earned") : L("Not yet"))
                }
            }
        }
        .padding(20)
    }

    // MARK: Records

    private var records: some View {
        let s = stats
        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                record(L("Games played"), "\(s.gamesPlayed)", "gamecontroller.fill")
                record(L("Time played"), L("{} h {} min", s.totalMinutes / 60, s.totalMinutes % 60), "clock.fill")
                record(L("Days played"), "\(s.daysPlayed)", "calendar")
                record(L("Coins earned"), "\(s.lifetimeCoins)", "star.fill")
                record(L("Items owned"), "\(s.itemsOwned) / \(ShopCatalogue.items.count)", "tshirt.fill")
                record(L("Pictures"), "\(s.pictures)", "photo.fill")
                record(L("Worlds made"), "\(s.worldsMade)", "hammer.fill")
                record(L("Best streak"), L("{} days", s.bestStreak), "flame.fill")
            }
            Text(L("Most played"))
                .font(.headline)
                .padding(.top, 6)
            ActivitySummary(log: settings.playtime)
        }
        .padding(20)
    }

    private func record(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ablox.Palette.inkMuted)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Album

    private var album: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pictures.isEmpty {
                EmptyStateView(title: L("No pictures yet"),
                               message: L("Take pictures while playing (the camera button), or in the photo booth."),
                               systemImage: "photo.on.rectangle")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(pictures, id: \.self) { url in
                    AlbumTile(url: url)
                        .contextMenu {
                            Button {
                                sharing = SharedFile(url: url)
                            } label: {
                                Label(L("Share or save to Files"), systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                ScreenshotStore.delete(url)
                                pictures = ScreenshotStore.all()
                            } label: {
                                Label(L("Delete"), systemImage: "trash")
                            }
                        }
                        .onTapGesture { sharing = SharedFile(url: url) }
                }
            }
        }
        .padding(20)
    }
}

/// One picture (or a clip) in the album.
private struct AlbumTile: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.06)
                Image(systemName: url.pathExtension.lowercased() == "png" ? "photo" : "film")
                    .font(.largeTitle)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: url) {
            guard url.pathExtension.lowercased() == "png" else { return }
            // Small, off the main thread: an album of big pictures should not
            // stutter the sheet.
            let path = url
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let full = UIImage(contentsOfFile: path.path) else { return nil }
                return full.preparingThumbnail(of: CGSize(width: 360, height: 220))
            }.value
        }
    }
}
