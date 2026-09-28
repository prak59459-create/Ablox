import SwiftUI
import UIKit
import AVKit
import AbloxCore

// The album, the second round: favourites and captions, grouped by day or
// by game, pictures or clips, a search, choosing several to share or
// delete, a full-screen viewer with a slideshow, clips that play, and
// editing a copy — a filter, a shape, a frame, a turn. Rules in
// AbloxCore/PhotoAlbum.swift.

struct AlbumView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore

    @State private var files: [(url: URL, entry: AlbumEntry)] = []
    @State private var show: AlbumShow = .all
    @State private var grouping: AlbumGrouping = .day
    @State private var newestFirst = true
    @State private var game: String?
    @State private var search = ""
    @State private var selecting = false
    @State private var chosen: Set<String> = []
    @State private var viewing: AlbumPage?
    @State private var sharing: [URL] = []
    @State private var confirmingDelete = false

    private var urls: [String: URL] {
        Dictionary(files.map { ($0.entry.id, $0.url) }, uniquingKeysWith: { first, _ in first })
    }

    private var shown: [AlbumEntry] {
        AlbumLayout.filter(files.map(\.entry), show: show, notes: settings.memory.albumNotes, game: game, search: search)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if files.isEmpty {
                EmptyStateView(title: L("No pictures yet"),
                               message: L("Take pictures while playing (the camera button), or in the photo booth."),
                               systemImage: "photo.on.rectangle")
            } else {
                summary
                controls
                sections
            }
        }
        .padding(20)
        .onAppear(perform: reload)
        .fullScreenCover(item: $viewing) { page in
            AlbumViewer(entries: page.entries, urls: urls, start: page.start) { reload() }
                .environmentObject(settings)
                .environmentObject(store)
        }
        .sheet(isPresented: Binding(get: { !sharing.isEmpty }, set: { if !$0 { sharing = [] } })) {
            ActivityShareSheet(items: sharing)
        }
        .alert(L("Delete {} pictures?", chosen.count), isPresented: $confirmingDelete) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete"), role: .destructive) {
                for id in chosen { if let url = urls[id] { ScreenshotStore.delete(url) } }
                chosen = []
                selecting = false
                reload()
            }
        }
    }

    private func reload() {
        files = ScreenshotStore.entries()
        // Notes about pictures deleted in Files go too.
        settings.memory.albumNotes.keepOnly(Set(files.map(\.entry.id)))
    }

    /// How many, and how much room they take.
    private var summary: some View {
        let pictures = files.filter { !$0.entry.isClip }.count
        let clips = files.count - pictures
        let bytes = files.reduce(0) { $0 + $1.entry.bytes }
        return HStack(spacing: 14) {
            Label(L("{} pictures", pictures), systemImage: "photo")
            if clips > 0 { Label(L("{} clips", clips), systemImage: "film") }
            Label(AlbumLayout.sizeText(bytes), systemImage: "internaldrive")
            Spacer()
            Button(selecting ? L("Done") : L("Choose")) {
                selecting.toggle()
                chosen = []
            }
            .font(.subheadline.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(Ablox.Palette.inkMuted)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            AbloxTextField(L("Search by game or caption"), text: $search)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Ablox.Palette.wash, in: Capsule())
            HStack(spacing: 8) {
                Picker(L("Show"), selection: $show) {
                    ForEach(AlbumShow.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Menu {
                    Picker(L("Group"), selection: $grouping) {
                        ForEach(AlbumGrouping.allCases) { Text($0.displayName).tag($0) }
                    }
                    Button(newestFirst ? L("Oldest first") : L("Newest first")) { newestFirst.toggle() }
                    Menu {
                        Button(L("Every game")) { game = nil }
                        ForEach(AlbumLayout.games(in: files.map(\.entry)), id: \.game) { item in
                            Button(L("{} ({})", item.game, item.count)) { game = item.game }
                        }
                    } label: {
                        Label(game ?? L("Every game"), systemImage: "gamecontroller")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                }
                .accessibilityLabel(L("Group and order"))
            }
            if selecting {
                HStack {
                    Text(L("{} chosen", chosen.count))
                    Spacer()
                    Button(L("Choose all")) { chosen = Set(shown.map(\.id)) }
                    Button {
                        sharing = chosen.compactMap { urls[$0] }
                    } label: {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(chosen.isEmpty)
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label(L("Delete"), systemImage: "trash")
                    }
                    .disabled(chosen.isEmpty)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var sections: some View {
        let groups = AlbumLayout.sections(shown, grouping: grouping, newestFirst: newestFirst)
        return VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty {
                Text(L("Nothing here yet."))
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            ForEach(groups.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    if grouping != .none {
                        Text(title(for: groups[index].section))
                            .font(.headline)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                        ForEach(groups[index].entries) { entry in
                            tile(entry, in: groups[index].entries)
                        }
                    }
                }
            }
        }
    }

    private func title(for section: AlbumSection) -> String {
        switch section {
        case .today: return L("Today")
        case .yesterday: return L("Yesterday")
        case let .day(date): return date.formatted(date: .complete, time: .omitted)
        case let .game(name): return name
        case .all: return ""
        }
    }

    private func tile(_ entry: AlbumEntry, in group: [AlbumEntry]) -> some View {
        let notes = settings.memory.albumNotes
        return AlbumThumb(url: urls[entry.id], isClip: entry.isClip)
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: chosen.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(chosen.contains(entry.id) ? Ablox.Palette.accent : .white)
                        .shadow(radius: 2)
                        .padding(6)
                } else if notes.isFavourite(entry.id) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Ablox.Palette.danger)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let caption = notes.caption(for: entry.id) {
                    Text(verbatim: caption)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
            }
            .onTapGesture {
                if selecting {
                    if chosen.contains(entry.id) { chosen.remove(entry.id) } else { chosen.insert(entry.id) }
                } else {
                    viewing = AlbumPage(entries: shown, start: shown.firstIndex(of: entry) ?? 0)
                }
            }
            .contextMenu {
                Button {
                    settings.memory.albumNotes.toggleFavourite(entry.id)
                } label: {
                    Label(notes.isFavourite(entry.id) ? L("Remove the heart") : L("Heart it"), systemImage: "heart")
                }
                if let url = urls[entry.id] {
                    Button {
                        sharing = [url]
                    } label: {
                        Label(L("Share or save to Files"), systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        ScreenshotStore.delete(url)
                        reload()
                    } label: {
                        Label(L("Delete"), systemImage: "trash")
                    }
                }
            }
            .accessibilityLabel(L("Picture from {}", entry.game))
    }
}

/// Which pictures the viewer pages through, and where it starts.
struct AlbumPage: Identifiable {
    let id = UUID()
    let entries: [AlbumEntry]
    let start: Int
}

/// A small picture, or a film symbol for a clip.
struct AlbumThumb: View {
    let url: URL?
    var isClip = false
    var height: CGFloat = 110
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Ablox.Palette.wash
                Image(systemName: isClip ? "film" : "photo")
                    .font(.largeTitle)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
            if isClip {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .task(id: url) {
            guard let url, !isClip else { return }
            let path = url
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let full = UIImage(contentsOfFile: path.path) else { return nil }
                return full.preparingThumbnail(of: CGSize(width: 360, height: 220))
            }.value
        }
    }
}

// MARK: - The viewer

struct AlbumViewer: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let entries: [AlbumEntry]
    let urls: [String: URL]
    let start: Int
    let onChange: () -> Void

    @State private var index = 0
    @State private var playing = false
    @State private var editing: URL?
    @State private var captioning = false
    @State private var caption = ""
    @State private var showingInfo = false
    @State private var sharing: SharedFile?
    @State private var notice: String?
    private let slideshow = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var current: AlbumEntry? { entries.indices.contains(index) ? entries[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(entries.indices, id: \.self) { position in
                    AlbumLargeView(url: urls[entries[position].id], isClip: entries[position].isClip)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            VStack {
                topBar
                Spacer()
                if let notice {
                    Text(notice)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                bottomBar
            }
            .foregroundStyle(.white)
        }
        .onAppear { index = min(max(0, start), max(0, entries.count - 1)) }
        .onReceive(slideshow) { _ in
            guard playing, !entries.isEmpty else { return }
            withAnimation { index = (index + 1) % entries.count }
        }
        .sheet(item: Binding(get: { editing.map(EditTarget.init) }, set: { editing = $0?.url })) { target in
            PhotoEditSheet(url: target.url) { saved in
                if let current { settings.memory.albumNotes.copy(current.id, to: saved.lastPathComponent) }
                say(L("A copy was saved to your album."))
                onChange()
            }
        }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
        .sheet(isPresented: $showingInfo) {
            if let current { AlbumInfoSheet(entry: current, url: urls[current.id]) }
        }
        .sheet(isPresented: $captioning) {
            TextPromptSheet(title: L("Caption"), message: L("A few words about this picture, only on this iPad."),
                            placeholder: L("Caption"), confirm: L("Save"), text: $caption) {
                if let current { settings.memory.albumNotes.setCaption(caption, for: current.id) }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(L("Close"))
            if let current {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: current.game)
                        .font(.headline)
                    Text(current.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .opacity(0.8)
                    if let text = settings.memory.albumNotes.caption(for: current.id) {
                        Text(verbatim: text)
                            .font(.caption.italic())
                    }
                }
            }
            Spacer()
            Text("\(index + 1) / \(entries.count)")
                .font(.caption.monospacedDigit())
            Button {
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.rectangle.fill")
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(playing ? L("Stop the slideshow") : L("Slideshow"))
        }
        .padding(18)
    }

    private var bottomBar: some View {
        let notes = settings.memory.albumNotes
        return HStack(spacing: 10) {
            if let current, let url = urls[current.id] {
                bar(notes.isFavourite(current.id) ? "heart.fill" : "heart", L("Heart it")) {
                    settings.memory.albumNotes.toggleFavourite(current.id)
                }
                bar("text.bubble", L("Caption")) {
                    caption = notes.caption(for: current.id) ?? ""
                    captioning = true
                }
                bar("info.circle", L("About this picture")) { showingInfo = true }
                bar("square.and.arrow.up", L("Share")) { sharing = SharedFile(url: url) }
                if !current.isClip {
                    bar("doc.on.doc", L("Copy")) {
                        if let image = UIImage(contentsOfFile: url.path) {
                            UIPasteboard.general.image = image
                            say(L("Copied"))
                        }
                    }
                    bar("slider.horizontal.3", L("Edit a copy")) { editing = url }
                    if let world = store.entries.first(where: { $0.name == current.game }) {
                        bar("photo.badge.checkmark", L("Use for my world")) {
                            if let image = UIImage(contentsOfFile: url.path),
                               let small = image.preparingThumbnail(of: CGSize(width: 480, height: 480 * image.size.height / max(1, image.size.width))),
                               let png = small.pngData() {
                                store.saveThumbnail(png, for: world.id)
                                say(L("This is now the picture for {}.", world.name))
                            }
                        }
                    }
                }
                bar("trash", L("Delete")) {
                    ScreenshotStore.delete(url)
                    onChange()
                    dismiss()
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
    }

    private func bar(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    private func say(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { if notice == text { notice = nil } }
        }
    }

    private struct EditTarget: Identifiable {
        let url: URL
        var id: URL { url }
    }
}

/// One picture filling the screen (pinch to look closer), or a clip that
/// plays.
struct AlbumLargeView: View {
    let url: URL?
    let isClip: Bool
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var zoomAtStart: CGFloat?

    var body: some View {
        Group {
            if isClip, let url {
                VideoPlayer(player: AVPlayer(url: url))
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoom)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                let base = zoomAtStart ?? zoom
                                if zoomAtStart == nil { zoomAtStart = base }
                                zoom = min(4, max(1, base * scale))
                            }
                            .onEnded { _ in zoomAtStart = nil }
                    )
                    .onTapGesture(count: 2) { withAnimation { zoom = zoom > 1 ? 1 : 2 } }
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            guard let url, !isClip else { return }
            let path = url
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: path.path) }.value
        }
    }
}

/// When and where a picture was taken, and how big it is.
struct AlbumInfoSheet: View {
    let entry: AlbumEntry
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var pixels: CGSize?

    var body: some View {
        NavigationStack {
            List {
                LabeledContent(L("Game"), value: entry.game)
                LabeledContent(L("Taken"), value: entry.date.formatted(date: .long, time: .standard))
                if let pixels {
                    LabeledContent(L("Size"), value: "\(Int(pixels.width)) × \(Int(pixels.height))")
                }
                LabeledContent(L("File"), value: AlbumLayout.sizeText(entry.bytes))
                LabeledContent(L("Kind"), value: entry.isClip ? L("Clip") : L("Picture"))
            }
            .navigationTitle(L("About this picture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .task {
            guard let url, !entry.isClip else { return }
            pixels = UIImage(contentsOfFile: url.path).map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
        }
    }
}

// MARK: - Editing a copy

/// A filter, a shape, a frame and a quarter turn, saved as a new picture so
/// the original is never lost.
struct PhotoEditSheet: View {
    let url: URL
    let onSaved: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var filter: PhotoFilter = .none
    @State private var options = PhotoModeOptions()
    @State private var turns = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Group {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxHeight: 360)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoFilter.allCases) { choice in
                            Button(choice.displayName) { filter = choice }
                                .buttonStyle(NeonButtonStyle(filter == choice ? .primary : .secondary))
                        }
                    }
                }
                HStack {
                    Picker(L("Shape"), selection: $options.crop) {
                        ForEach(PhotoCrop.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker(L("Frame"), selection: $options.frame) {
                        ForEach(PhotoFrame.allCases) { Text($0.displayName).tag($0) }
                    }
                    Button {
                        turns = (turns + 1) % 4
                    } label: {
                        Label(L("Turn"), systemImage: "rotate.right")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                }
            }
            .padding(20)
            .navigationTitle(L("Edit a copy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save a copy")) {
                        if let finished = render(), let saved = ScreenshotStore.saveCopy(finished, of: url) {
                            onSaved(saved)
                        }
                        dismiss()
                    }
                    .disabled(original == nil)
                }
            }
        }
        .abloxColorScheme()
        .task {
            let path = url
            original = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: path.path) }.value
            preview = render()
        }
        .onChange(of: filter) { _, _ in preview = render() }
        .onChange(of: options) { _, _ in preview = render() }
        .onChange(of: turns) { _, _ in preview = render() }
    }

    private func render() -> UIImage? {
        guard let original else { return nil }
        var image = filter.apply(to: original)
        if turns > 0 { image = rotated(image, quarterTurns: turns) }
        return PhotoComposer.compose(image, options: options, game: AlbumEntry.parse(url.lastPathComponent)?.game ?? "")
    }

    private func rotated(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let size = quarterTurns % 2 == 1 ? CGSize(width: image.size.height, height: image.size.width) : image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: CGFloat(quarterTurns) * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
}

// MARK: - A game's pictures

/// Pictures taken in one game, for its page in the Games tab.
struct GamePicturesRow: View {
    let game: String
    @State private var files: [(url: URL, entry: AlbumEntry)] = []
    @State private var sharing: SharedFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !files.isEmpty {
                Text(L("My pictures from this game ({})", files.count))
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(files.prefix(12), id: \.entry.id) { file in
                            AlbumThumb(url: file.url, isClip: file.entry.isClip, height: 90)
                                .frame(width: 150)
                                .onTapGesture { sharing = SharedFile(url: file.url) }
                        }
                    }
                }
            }
        }
        .onAppear { files = ScreenshotStore.entries().filter { $0.entry.game == game } }
        .sheet(item: $sharing) { file in
            ActivityShareSheet(items: [file.url])
        }
    }
}
