import SwiftUI
import UIKit
import ReplayKit
import CoreImage
import AbloxCore

// The play screen's extras: pictures and clips, emotes, the map, the pause
// menu, and the little status chips. Each is small and on its own, so the
// play screen reads as a list of what is on it.

// MARK: - Sharing

/// The system share sheet, without "Save Image" — saving to Photos needs a
/// permission this app does not ask for, and would crash without it. Files,
/// AirDrop and Messages still work.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = [.saveToCameraRoll, .assignToContact]
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file waiting to be shared.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Screenshots

/// Pictures taken in games, kept in the app's own folder (Documents/Album)
/// for the album in the menu, and shared from there.
enum ScreenshotStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Album", isDirectory: true)
    }

    /// Saves a picture and returns where, or nil.
    static func save(_ image: UIImage, game: String) -> URL? {
        guard let data = image.pngData() else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let safe = game.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined().prefix(40)
        let url = folder.appendingPathComponent("\(safe) \(formatter.string(from: Date())).png")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    /// Every picture, newest first.
    static func all() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        return files.filter { ["png", "jpg", "mp4", "mov"].contains($0.pathExtension.lowercased()) }.sorted { date($0) > date($1) }
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Every picture and clip with what its name says, newest first.
    static func entries() -> [(url: URL, entry: AlbumEntry)] {
        all().compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            guard let entry = AlbumEntry.parse(url.lastPathComponent, bytes: values?.fileSize ?? 0,
                                               fallbackDate: values?.creationDate ?? .distantPast) else { return nil }
            return (url, entry)
        }
    }

    /// An edited picture saved beside the one it came from.
    static func saveCopy(_ image: UIImage, of original: URL) -> URL? {
        let game = AlbumEntry.parse(original.lastPathComponent)?.game ?? L("Edited")
        return save(image, game: game)
    }
}

/// A look for photo mode, applied to the picture as it is taken.
enum PhotoFilter: String, CaseIterable, Identifiable {
    case none, vivid, warm, cool, mono, retro
    // The second round.
    case noir, fade, chrome, instant, process, transfer, tonal, bloom, vignette, comic, pixel, poster

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return L("Normal")
        case .vivid: return L("Vivid")
        case .warm: return L("Warm")
        case .cool: return L("Cool")
        case .mono: return L("Black and white")
        case .retro: return L("Retro")
        case .noir: return L("Noir")
        case .fade: return L("Faded")
        case .chrome: return L("Chrome")
        case .instant: return L("Instant")
        case .process: return L("Process")
        case .transfer: return L("Transfer")
        case .tonal: return L("Tonal")
        case .bloom: return L("Glow")
        case .vignette: return L("Vignette")
        case .comic: return L("Comic")
        case .pixel: return L("Pixels")
        case .poster: return L("Poster")
        }
    }

    /// The same look, roughly, as a SwiftUI overlay while framing the shot.
    var previewTint: Color {
        switch self {
        case .none, .vivid: return .clear
        case .warm: return Color.orange.opacity(0.18)
        case .cool: return Color.blue.opacity(0.16)
        case .mono: return Color.gray.opacity(0.35)
        case .retro: return Color(red: 0.7, green: 0.5, blue: 0.25).opacity(0.25)
        case .noir, .tonal: return Color.black.opacity(0.3)
        case .fade: return Color.white.opacity(0.2)
        case .chrome, .process: return Color.teal.opacity(0.12)
        case .instant, .transfer: return Color(red: 0.9, green: 0.75, blue: 0.5).opacity(0.18)
        case .bloom: return Color.white.opacity(0.12)
        case .vignette: return Color.black.opacity(0.12)
        case .comic, .pixel, .poster: return .clear
        }
    }

    func apply(to image: UIImage) -> UIImage {
        guard self != .none, let input = CIImage(image: image) else { return image }
        var output = input
        switch self {
        case .none:
            break
        case .vivid:
            output = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4, kCIInputContrastKey: 1.1])
        case .warm:
            output = input.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 4800, y: 0)])
        case .cool:
            output = input.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 9000, y: 0)])
        case .mono:
            output = input.applyingFilter("CIPhotoEffectMono")
        case .retro:
            output = input.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.6])
        case .noir: output = input.applyingFilter("CIPhotoEffectNoir")
        case .fade: output = input.applyingFilter("CIPhotoEffectFade")
        case .chrome: output = input.applyingFilter("CIPhotoEffectChrome")
        case .instant: output = input.applyingFilter("CIPhotoEffectInstant")
        case .process: output = input.applyingFilter("CIPhotoEffectProcess")
        case .transfer: output = input.applyingFilter("CIPhotoEffectTransfer")
        case .tonal: output = input.applyingFilter("CIPhotoEffectTonal")
        case .bloom:
            output = input.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 12, kCIInputIntensityKey: 0.8])
        case .vignette:
            output = input.applyingFilter("CIVignette", parameters: [kCIInputRadiusKey: 2, kCIInputIntensityKey: 1.2])
        case .comic: output = input.applyingFilter("CIComicEffect")
        case .pixel:
            // Blocks sized to the picture, so a big screen is not a blur.
            let scale = max(6, min(input.extent.width, input.extent.height) / 90)
            output = input.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale])
        case .poster:
            output = input.applyingFilter("CIColorPosterize", parameters: ["inputLevels": 6])
        }
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Clips

/// The last thirty seconds of play, on request. ReplayKit keeps a rolling
/// buffer once it is switched on (iPadOS asks the player first), and saves
/// the end of it when asked.
@MainActor
final class ClipRecorder: ObservableObject {
    @Published private(set) var isBuffering = false
    @Published private(set) var isSaving = false
    @Published var lastError: String?

    func toggle() {
        isBuffering ? stop() : start()
    }

    func start() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable, !recorder.isRecording else {
            lastError = L("Recording is not available right now.")
            return
        }
        recorder.startClipBuffering { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    self?.isBuffering = false
                } else {
                    self?.isBuffering = true
                }
            }
        }
    }

    func stop() {
        RPScreenRecorder.shared().stopClipBuffering { [weak self] _ in
            Task { @MainActor in self?.isBuffering = false }
        }
    }

    /// Saves the last `seconds` into the album and hands back where.
    func saveClip(seconds: TimeInterval = 30, game: String, completion: @escaping (URL?) -> Void) {
        guard isBuffering else { return completion(nil) }
        isSaving = true
        try? FileManager.default.createDirectory(at: ScreenshotStore.folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = ScreenshotStore.folder.appendingPathComponent("\(game.prefix(40)) \(formatter.string(from: Date())).mp4")
        RPScreenRecorder.shared().exportClip(to: url, duration: seconds) { [weak self] error in
            Task { @MainActor in
                self?.isSaving = false
                if let error {
                    self?.lastError = error.localizedDescription
                    completion(nil)
                } else {
                    completion(url)
                }
            }
        }
    }
}

// MARK: - Emotes

/// Emotes and emoji stamps, in a panel that opens from the top bar.
struct EmotePanel: View {
    let onChoose: (Gesture) -> Void
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let favourites = settings.memory.emotes
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Hold one to make it a favourite (keys 1–4)."))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    if let any = Emote.allCases.filter({ $0 != .sit }).randomElement() { onChoose(.emote(any)) }
                } label: {
                    Label(L("Surprise me"), systemImage: "dice.fill")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Ablox.Palette.accent)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 4), spacing: 8) {
                        ForEach(favourites.ordered, id: \.self) { emote in
                            emoteButton(emote, favourite: favourites.contains(emote))
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 6), count: 6), spacing: 6) {
                        ForEach(Stamp.all, id: \.self) { emoji in
                            Button {
                                onChoose(.stamp(emoji))
                            } label: {
                                Text(verbatim: emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 42, height: 42)
                                    .background(Color.white.opacity(0.08), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 330)
        }
        .padding(14)
        .frame(width: 310)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func emoteButton(_ emote: Emote, favourite: Bool) -> some View {
        Button {
            onChoose(.emote(emote))
        } label: {
            VStack(spacing: 4) {
                Image(systemName: emote.symbolName)
                    .font(.title3)
                Text(emote.displayName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 64, height: 58)
            .background(Color.white.opacity(favourite ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if favourite {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).padding(4)
                }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            settings.memory.emotes.toggle(emote)
        })
        .accessibilityAction(named: favourite ? L("Remove from favourites") : L("Add to favourites")) {
            settings.memory.emotes.toggle(emote)
        }
    }
}

// MARK: - Map

/// The world from above: small in the corner around the player, or the
/// whole of it. North is up (or, if the player chose, the way the camera
/// looks); the player is the arrow and friends have a gold ring.
struct MiniMapView: View {
    let world: WorldDocument
    let players: [PlayerSnapshot]
    let localPeerID: PeerID
    let expanded: Bool
    /// Metres across the small map.
    var metresAcross: Double = 80
    /// The camera's bearing, to turn the small map so it is up; nil keeps
    /// north up.
    var heading: Float?
    var friends: Set<PeerID> = []

    private struct Plot {
        let rect: CGRect
        let color: Color
    }

    /// The world's footprint, worked out once per revision of the world.
    private final class Cache {
        static let shared = Cache()
        var key: String = ""
        var plots: [Plot] = []
        var bounds = CGRect(x: -50, y: -50, width: 100, height: 100)
    }

    private func plots() -> (plots: [Plot], bounds: CGRect) {
        let cache = Cache.shared
        let key = world.id.uuidString + "\(world.modifiedAt.timeIntervalSince1970)-\(world.blocks.count)"
        if cache.key == key { return (cache.plots, cache.bounds) }
        let index = WorldIndex(world: world)
        var made: [(Plot, Float)] = []
        var minX = Float.infinity, minZ = Float.infinity, maxX = -Float.infinity, maxZ = -Float.infinity
        for (entry, block) in zip(index.entries, world.blocks) where entry.isVisible && block.color.a > 0.15 {
            let b = entry.bounds
            let width = b.max.x - b.min.x, depth = b.max.z - b.min.z
            guard width.isFinite, depth.isFinite, width > 0.05 || depth > 0.05, width < 2000, depth < 2000 else { continue }
            let rect = CGRect(x: CGFloat(b.min.x), y: CGFloat(b.min.z), width: CGFloat(max(width, 0.3)), height: CGFloat(max(depth, 0.3)))
            made.append((Plot(rect: rect, color: Color(block.color)), b.max.y))
            if width < 400 && depth < 400 {
                minX = min(minX, b.min.x); maxX = max(maxX, b.max.x)
                minZ = min(minZ, b.min.z); maxZ = max(maxZ, b.max.z)
            }
        }
        // Low things first, so a roof is drawn over the floor under it.
        made.sort { $0.1 < $1.1 }
        let kept = made.count > 6000 ? Array(made.suffix(6000)) : made
        cache.key = key
        cache.plots = kept.map(\.0)
        cache.bounds = minX.isFinite
            ? CGRect(x: CGFloat(minX), y: CGFloat(minZ), width: CGFloat(max(20, maxX - minX)), height: CGFloat(max(20, maxZ - minZ)))
            : CGRect(x: -50, y: -50, width: 100, height: 100)
        return (cache.plots, cache.bounds)
    }

    var body: some View {
        let (plots, worldBounds) = plots()
        let me = players.first { $0.peerID == localPeerID }
        let turn = expanded ? nil : heading
        Canvas { context, size in
            // What part of the world is on the map.
            let view: CGRect
            if expanded {
                let pad = max(worldBounds.width, worldBounds.height) * 0.06
                view = worldBounds.insetBy(dx: -pad, dy: -pad)
            } else {
                let centre = CGPoint(x: CGFloat(me?.position.x ?? 0), y: CGFloat(me?.position.z ?? 0))
                let across = CGFloat(metresAcross)
                view = CGRect(x: centre.x - across / 2, y: centre.y - across / 2, width: across, height: across)
            }
            let scale = min(size.width / view.width, size.height / view.height)
            let offset = CGPoint(x: (size.width - view.width * scale) / 2, y: (size.height - view.height * scale) / 2)
            func point(_ x: CGFloat, _ z: CGFloat) -> CGPoint {
                CGPoint(x: offset.x + (x - view.minX) * scale, y: offset.y + (z - view.minY) * scale)
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.55)))
            // Turned, the corners show ground beyond the square.
            let visible = turn == nil ? view : view.insetBy(dx: -view.width * 0.21, dy: -view.height * 0.21)
            let original = context
            if let turn {
                context.translateBy(x: size.width / 2, y: size.height / 2)
                context.rotate(by: .degrees(Double(-turn)))
                context.translateBy(x: -size.width / 2, y: -size.height / 2)
            }
            for plot in plots where plot.rect.intersects(visible) {
                let origin = point(plot.rect.minX, plot.rect.minY)
                let rect = CGRect(x: origin.x, y: origin.y, width: max(1, plot.rect.width * scale), height: max(1, plot.rect.height * scale))
                context.fill(Path(rect), with: .color(plot.color.opacity(0.85)))
            }
            for player in players where !player.isHidden && player.peerID != localPeerID {
                let p = point(CGFloat(player.position.x), CGFloat(player.position.z))
                let r: CGFloat = player.isNPC ? 2.5 : 4
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(player.isNPC ? Color.red.opacity(0.8) : Color(player.profile.bodyColor)))
                if friends.contains(player.peerID) {
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - r - 1.5, y: p.y - r - 1.5, width: r * 2 + 3, height: r * 2 + 3)),
                                   with: .color(Ablox.Palette.warning), lineWidth: 2)
                } else if !player.isNPC {
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white), lineWidth: 1)
                }
            }
            if let me {
                let p = point(CGFloat(me.position.x), CGFloat(me.position.z))
                // Yaw 0 faces -z, which is up on the map.
                let angle = Angle(degrees: Double(me.yawDegrees)).radians
                var arrow = Path()
                arrow.move(to: CGPoint(x: 0, y: -8))
                arrow.addLine(to: CGPoint(x: 5.5, y: 6))
                arrow.addLine(to: CGPoint(x: 0, y: 3))
                arrow.addLine(to: CGPoint(x: -5.5, y: 6))
                arrow.closeSubpath()
                let placed = arrow.applying(CGAffineTransform(rotationAngle: CGFloat(-angle))).applying(CGAffineTransform(translationX: p.x, y: p.y))
                context.fill(placed, with: .color(.white))
                context.stroke(placed, with: .color(Ablox.Palette.accent), lineWidth: 1.5)
            }
            if let turn {
                // Where north is, on the turned map.
                let angle = Angle(degrees: Double(-turn)).radians
                let reach = min(size.width, size.height) / 2 - 10
                let at = CGPoint(x: size.width / 2 + CGFloat(sin(angle)) * reach, y: size.height / 2 - CGFloat(cos(angle)) * reach)
                original.draw(Text(L("N")).font(.system(size: 11, weight: .black)).foregroundStyle(Ablox.Palette.danger), at: at)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 18 : 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 18 : 14, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .accessibilityLabel(L("Map"))
    }
}

// MARK: - Status chips

/// Ping as signal bars, in the corner.
struct NetworkBadge: View {
    let ping: Double?
    let isReconnecting: Bool

    private var bars: Int {
        guard !isReconnecting, let ping else { return 0 }
        return ping < 40 ? 3 : ping < 100 ? 2 : 1
    }

    var body: some View {
        HStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...3, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(colour(ofBar: level))
                        .frame(width: 4, height: height(ofBar: level))
                }
            }
            Text(caption)
                .font(.caption2.weight(.bold).monospacedDigit())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func colour(ofBar level: Int) -> Color {
        guard level <= bars else { return Color.white.opacity(0.25) }
        return bars >= 2 ? Ablox.Palette.success : Ablox.Palette.warning
    }

    private func height(ofBar level: Int) -> CGFloat {
        CGFloat(4 + level * 4)
    }

    private var caption: String {
        if isReconnecting { return L("Reconnecting") }
        guard let ping else { return L("Local") }
        return L("{}ms", Int(ping))
    }

    private var spoken: String {
        isReconnecting ? L("Reconnecting") : L("Connection: {} of 3 bars", bars)
    }
}

/// How long this visit has lasted.
struct PlayClockChip: View {
    let seconds: Double

    var body: some View {
        let total = Int(seconds)
        Label(String(format: "%d:%02d", total / 60, total % 60), systemImage: "clock")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
    }
}

// MARK: - Pause menu

/// Everything that is not playing: resume, pictures and clips, the camera,
/// the controls, what the game said, how to play, and the way out.
struct PauseMenu: View {
    @ObservedObject var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var clips: ClipRecorder
    @Binding var preferFirstPerson: Bool
    /// "Ten more minutes", set here by the player.
    @Binding var selfTimer: SelfTimer
    let playSeconds: Double
    let onResume: () -> Void
    let onScreenshot: () -> Void
    let onSaveClip: () -> Void
    let onPhotoMode: () -> Void
    let onReturnToStart: () -> Void
    let onEditButtons: () -> Void
    let onLeave: () -> Void
    /// The visit so far, and the play screen's extras (HUDExtras.swift).
    let tracker: PlayTracker
    let onCameraBehind: () -> Void
    let onHideButtons: () -> Void
    let onShortcuts: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case game, room, controls, messages, help
        var id: String { rawValue }
        var title: String {
            switch self {
            case .game: return L("Game")
            case .room: return L("Room")
            case .controls: return L("Controls")
            case .messages: return L("Messages")
            case .help: return L("How to play")
            }
        }
    }

    @State private var tab: Tab = .game
    @State private var confirmingStart = false
    @State private var choosingHowToLeave = false
    @State private var showingOptions = false
    @State private var copiedCode = false

    /// The room tab only means something with other people.
    private var tabs: [Tab] {
        session.isSolo ? Tab.allCases.filter { $0 != .room } : Tab.allCases
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onResume)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(session.isPaused ? L("Paused") : L("Menu"))
                        .font(.title2.weight(.bold))
                    if session.isSolo {
                        Badge(L("The game has stopped"), color: Ablox.Palette.accent, systemImage: "pause.fill")
                    }
                    Spacer()
                    PlayClockChip(seconds: playSeconds)
                }
                Picker(L("Menu"), selection: $tab) {
                    ForEach(tabs) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    switch tab {
                    case .game: gameTab
                    case .room: RoomMenuTab(session: session)
                    case .controls: controlsTab
                    case .messages: messagesTab
                    case .help: helpTab
                    }
                }
                .frame(maxHeight: 360)

                HStack(spacing: 10) {
                    Button(action: onResume) {
                        Label(L("Resume"), systemImage: "play.fill")
                    }
                    .buttonStyle(NeonButtonStyle(.primary))
                    Spacer()
                    Button(role: .destructive) {
                        // A host with people still playing can hand the room on
                        // rather than close it on them.
                        if session.canHandOver { choosingHowToLeave = true } else { onLeave() }
                    } label: {
                        Label(L("Leave world"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                    .leaveRoomChoice(isPresented: $choosingHowToLeave, session: session, onLeave: onLeave)
                }
            }
            .padding(22)
            .frame(maxWidth: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .foregroundStyle(.white)
        }
        .alert(L("Go back to the start?"), isPresented: $confirmingStart) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Go back")) { onReturnToStart() }
        } message: {
            Text(L("You'll be put back where the world begins."))
        }
        .sheet(isPresented: $showingOptions) {
            PlayScreenOptionsView()
        }
    }

    private var gameTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            VisitStatsCard(tally: tracker.tally, seconds: playSeconds, score: session.localPlayer?.score ?? 0)
            // Experience needs neither worlds nor pictures.
            LevelCard(level: settings.progressStats(worldsMade: 0, pictures: 0).level)
            row(L("Take a picture"), "camera.fill", action: onScreenshot)
            row(L("Photo mode"), "camera.aperture", action: onPhotoMode)
            row(clips.isBuffering ? L("Save the last 30 seconds") : L("Start keeping clips"),
                clips.isBuffering ? "film.stack" : "record.circle", action: clips.isBuffering ? onSaveClip : { clips.start() })
            if clips.isBuffering {
                row(L("Stop keeping clips"), "stop.circle") { clips.stop() }
            }
            if let error = clips.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.warning)
            }
            row(L("Back to the start"), "arrow.uturn.backward.circle") { confirmingStart = true }
            row(L("Camera behind me"), "camera.rotate", action: onCameraBehind)
            row(L("Hide the buttons"), "eye.slash", action: onHideButtons)
            row(L("Keyboard shortcuts"), "keyboard", action: onShortcuts)
            if session.role == .hosting, !session.roomCode.isEmpty {
                row(copiedCode ? L("Copied!") : L("Copy the room code"), copiedCode ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = RoomCode.formatted(session.roomCode)
                    copiedCode = true
                }
            }
            timerRow
        }
    }

    /// A timer of the player's own: a minute's warning, then this menu.
    @ViewBuilder private var timerRow: some View {
        if let left = selfTimer.remaining() {
            HStack {
                Image(systemName: "timer")
                    .frame(width: 26)
                    .foregroundStyle(Ablox.Palette.warning)
                Text(L("My timer: {} left", SelfTimer.clock(left)))
                Spacer()
                Button(L("Stop")) { selfTimer.cancel() }
                    .font(.caption.weight(.bold))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Menu {
                ForEach(SelfTimer.choices, id: \.self) { minutes in
                    Button(L("{} minutes", minutes)) { selfTimer.start(minutes: minutes) }
                }
            } label: {
                HStack {
                    Image(systemName: "timer")
                        .frame(width: 26)
                        .foregroundStyle(Ablox.Palette.accent)
                    Text(L("Set my own timer"))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Ablox.Palette.inkFaint)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .foregroundStyle(.white)
        }
    }

    private var controlsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.scripted.camera.mode == .thirdPerson {
                Toggle(L("First-person camera"), isOn: $preferFirstPerson)
                    .tint(Ablox.Palette.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Camera distance"))
                    .font(.subheadline.weight(.medium))
                Slider(value: $settings.preferences.cameraZoom, in: PlayPreferences.cameraZoomRange)
                    .tint(Ablox.Palette.accent)
            }
            Toggle(L("Auto-jump"), isOn: $settings.preferences.autoJump)
                .tint(Ablox.Palette.accent)
            Toggle(L("Stick on the right"), isOn: $settings.joystickOnRight)
                .tint(Ablox.Palette.accent)
            Toggle(L("Camera follows behind me"), isOn: $settings.preferences.hud.cameraFollows)
                .tint(Ablox.Palette.accent)
            CrosshairPickers()
            Toggle(L("One-handed controls"), isOn: $settings.preferences.oneHanded)
                .tint(Ablox.Palette.accent)
            Toggle(L("Show the map"), isOn: $settings.preferences.showMap)
                .tint(Ablox.Palette.accent)
            Toggle(L("Show the play clock"), isOn: $settings.preferences.showClock)
                .tint(Ablox.Palette.accent)
            Toggle(L("Show connection"), isOn: $settings.preferences.showNetworkStatus)
                .tint(Ablox.Palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sound effects"))
                    .font(.subheadline.weight(.medium))
                Slider(value: $settings.preferences.effectsVolume, in: 0...1)
                    .tint(Ablox.Palette.accent)
                Text(L("Music"))
                    .font(.subheadline.weight(.medium))
                Slider(value: $settings.preferences.musicVolume, in: 0...1)
                    .tint(Ablox.Palette.accent)
            }
            Toggle(L("Read characters' lines aloud"), isOn: $settings.preferences.readLinesAloud)
                .tint(Ablox.Palette.accent)
            HStack {
                Button(action: onEditButtons) {
                    Label(L("Move and resize the buttons"), systemImage: "hand.draw")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
                Button {
                    showingOptions = true
                } label: {
                    Label(L("More options"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(NeonButtonStyle(.secondary))
            }
        }
    }

    private var messagesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            // What people said, all of it, when there are people to say it.
            if !session.isSolo || !session.chatLog.isEmpty {
                ChatHistoryList(session: session)
                Divider().background(Color.white.opacity(0.1))
            }
            if session.messageLog.isEmpty {
                Text(L("Nothing yet. Banners and messages from the game are kept here."))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            ForEach(session.messageLog.reversed()) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Ablox.Palette.inkFaint)
                    Text(verbatim: entry.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // What the app itself said at the bottom of the screen.
            let notices = tracker.notices
            if !notices.isEmpty {
                Text(L("Notices this visit"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Ablox.Palette.inkMuted)
                    .padding(.top, 8)
                ForEach(notices.indices.reversed(), id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text(notices[index].date.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Ablox.Palette.inkFaint)
                        Text(verbatim: notices[index].text)
                            .font(.subheadline)
                            .foregroundStyle(Ablox.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var helpTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: session.world.name)
                .font(.headline)
            if !session.world.authorName.isEmpty {
                Text(L("Made by {}", session.world.authorName))
                    .font(.subheadline)
                    .foregroundStyle(Ablox.Palette.inkMuted)
            }
            Text(L("Many games explain themselves when you arrive — look for their own help button on the screen."))
                .font(.caption)
                .foregroundStyle(Ablox.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Divider().background(Color.white.opacity(0.1))
            Label(L("Drag on the left to walk; push all the way to run."), systemImage: "hand.draw")
            Label(L("Drag on the right to look around. Pinch to zoom. Tap twice to put the camera behind you."),
                  systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            Label(L("The arrow button jumps."), systemImage: "arrow.up.circle")
            Label(L("Tap things in the world to use them."), systemImage: "hand.tap")
            Label(L("Buttons the game puts on the screen do what they say."), systemImage: "rectangle.and.hand.point.up.left")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 26)
                    .foregroundStyle(Ablox.Palette.accent)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Ablox.Palette.inkFaint)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Button layout

/// Drag the jump button where the thumb wants it, and choose its size.
struct ButtonLayoutEditor: View {
    @Binding var preferences: PlayPreferences
    let stickOnLeft: Bool
    let onDone: () -> Void
    @State private var dragStart: PlayPreferences.PointOffset?

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("Drag the jump button where you like it"))
                    .font(.headline)
                HStack {
                    Text(L("Size"))
                    Slider(value: $preferences.buttonScale, in: PlayPreferences.buttonScaleRange)
                        .tint(Ablox.Palette.accent)
                        .frame(width: 220)
                }
                HStack(spacing: 12) {
                    Button(L("Reset")) {
                        preferences.jumpButtonOffset = PlayPreferences.PointOffset()
                        preferences.buttonScale = 1
                    }
                    .buttonStyle(NeonButtonStyle(.secondary))
                    Button(L("Done"), action: onDone)
                        .buttonStyle(NeonButtonStyle(.primary))
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(.white)

            VStack {
                Spacer()
                HStack {
                    if stickOnLeft { Spacer() }
                    ghost
                    if !stickOnLeft { Spacer() }
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 44)
            }
        }
    }

    private var ghost: some View {
        Circle()
            .fill(Ablox.Palette.accent.opacity(0.35))
            .overlay(Circle().strokeBorder(Ablox.Palette.accent, style: StrokeStyle(lineWidth: 3, dash: [6, 4])))
            .overlay(Image(systemName: "arrow.up").font(.system(size: 26, weight: .bold)).foregroundStyle(.white))
            .frame(width: 76, height: 76)
            .scaleEffect(preferences.buttonScale)
            .offset(x: preferences.jumpButtonOffset.x, y: preferences.jumpButtonOffset.y)
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        let start = dragStart ?? preferences.jumpButtonOffset
                        if dragStart == nil { dragStart = start }
                        preferences.jumpButtonOffset = PlayPreferences.PointOffset(
                            x: start.x + drag.translation.width, y: start.y + drag.translation.height)
                        preferences.clamp()
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}
