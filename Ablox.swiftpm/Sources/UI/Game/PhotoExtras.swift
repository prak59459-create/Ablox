import SwiftUI
import UIKit

// Photo mode, the second round: a timer and bursts, lines in thirds, the
// picture's shape, a frame and a stamp, a zoom lens, poses, a flash, and the
// last picture in the corner. Rules in AbloxCore/PhotoAlbum.swift.

// MARK: - Finishing a picture

enum PhotoComposer {

    /// The picture cut to its shape, then framed and stamped as chosen.
    static func compose(_ image: UIImage, options: PhotoModeOptions, game: String, date: Date = Date()) -> UIImage {
        var picture = image
        if options.crop != .original, let cg = image.cgImage {
            let r = options.crop.rect(width: Double(cg.width), height: Double(cg.height))
            if let cut = cg.cropping(to: CGRect(x: r.x, y: r.y, width: r.width, height: r.height)) {
                picture = UIImage(cgImage: cut, scale: image.scale, orientation: image.imageOrientation)
            }
        }
        guard options.frame != .none || options.stamp else { return picture }
        let size = picture.size
        let framed = options.frame.framedSize(width: Double(size.width), height: Double(size.height))
        let unit = min(size.width, size.height)
        let borders = options.frame.borders
        let origin = CGPoint(x: CGFloat(borders.side) * unit, y: CGFloat(borders.top) * unit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = picture.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: framed.width, height: framed.height), format: format)
        return renderer.image { context in
            options.frame.colour.uiColor.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: framed.width, height: framed.height)))
            if options.frame == .film { drawFilmHoles(in: CGSize(width: framed.width, height: framed.height), unit: unit) }
            picture.draw(in: CGRect(origin: origin, size: size))
            if options.stamp {
                drawStamp(PhotoModeOptions.stampText(game: game, date: date), in: CGRect(origin: origin, size: size), unit: unit)
            }
        }
    }

    /// Sprocket holes along a film frame's top and bottom.
    private static func drawFilmHoles(in size: CGSize, unit: CGFloat) {
        let hole = CGSize(width: unit * 0.035, height: unit * 0.04)
        let gap = unit * 0.07
        UIColor(white: 0.9, alpha: 0.9).setFill()
        var x = gap / 2
        while x + hole.width < size.width {
            for y in [unit * 0.025, size.height - unit * 0.025 - hole.height] {
                UIBezierPath(roundedRect: CGRect(x: x, y: y, width: hole.width, height: hole.height), cornerRadius: hole.width * 0.2).fill()
            }
            x += gap
        }
    }

    /// The game and date in the lower right, like an old camera.
    private static func drawStamp(_ text: String, in rect: CGRect, unit: CGFloat) {
        let font = UIFont.monospacedDigitSystemFont(ofSize: max(12, unit * 0.035), weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 0.95),
            .strokeColor: UIColor.black.withAlphaComponent(0.5),
            .strokeWidth: -2
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        let margin = unit * 0.03
        string.draw(at: CGPoint(x: rect.maxX - bounds.width - margin, y: rect.maxY - bounds.height - margin))
    }
}

// MARK: - While framing

/// Lines in thirds, inside the shape the picture will be cut to.
struct ThirdsGrid: View {
    let crop: PhotoCrop

    var body: some View {
        GeometryReader { proxy in
            let r = crop.rect(width: Double(proxy.size.width), height: Double(proxy.size.height))
            let frame = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
            Path { path in
                for i in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(i) / 3
                    let y = frame.minY + frame.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY))
                    path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: y))
                    path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 1)
            if crop != .original {
                // The part that will be cut away, dimmed.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addRect(frame)
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Photo mode's choices, in a row of small menus: timer, burst, grid,
/// shape, frame, stamp.
struct PhotoOptionsBar: View {
    @Binding var options: PhotoModeOptions

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(PhotoModeOptions.timerChoices, id: \.self) { seconds in
                    Button(seconds == 0 ? L("No timer") : L("{} seconds", seconds)) { options.timer = seconds }
                }
            } label: {
                pill(options.timer == 0 ? L("Timer") : L("{} s", options.timer), "timer", on: options.timer > 0)
            }
            Button {
                options.burst.toggle()
            } label: {
                pill(L("Burst"), "square.stack.3d.down.right", on: options.burst)
            }
            Button {
                options.grid.toggle()
            } label: {
                pill(L("Grid"), "grid", on: options.grid)
            }
            Menu {
                ForEach(PhotoCrop.allCases) { crop in
                    Button(crop.displayName) { options.crop = crop }
                }
            } label: {
                pill(options.crop.displayName, "crop", on: options.crop != .original)
            }
            Menu {
                ForEach(PhotoFrame.allCases) { frame in
                    Button(frame.displayName) { options.frame = frame }
                }
            } label: {
                pill(options.frame == .none ? L("Frame") : options.frame.displayName, "photo.artframe", on: options.frame != .none)
            }
            Button {
                options.stamp.toggle()
            } label: {
                pill(L("Date stamp"), "calendar", on: options.stamp)
            }
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, _ symbol: String, on: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(on ? Ablox.Palette.accent.opacity(0.45) : Color.black.opacity(0.35), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// Zoom, and poses for the avatar while framing.
struct PhotoPoseBar: View {
    @Binding var zoom: Float
    let poses: [Emote]
    let onPose: (Emote) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass")
            Slider(value: Binding(get: { -zoom }, set: { zoom = -$0 }),
                   in: -PhotoModeOptions.zoomRange.upperBound...(-PhotoModeOptions.zoomRange.lowerBound))
                .frame(width: 180)
                .tint(Ablox.Palette.accent)
                .accessibilityLabel(L("Zoom"))
            Image(systemName: "plus.magnifyingglass")
            Divider().frame(height: 24).background(Color.white.opacity(0.3))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(poses, id: \.self) { pose in
                        Button {
                            onPose(pose)
                        } label: {
                            Image(systemName: pose.symbolName)
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.35), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pose.displayName)
                    }
                }
            }
            .frame(maxWidth: 320)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// The last picture taken, small, to open.
struct LastShotButton: View {
    let url: URL?
    let action: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel(L("The last picture"))
        .task(id: url) {
            guard let url else { image = nil; return }
            let path = url
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                UIImage(contentsOfFile: path.path)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
            }.value
        }
    }
}
