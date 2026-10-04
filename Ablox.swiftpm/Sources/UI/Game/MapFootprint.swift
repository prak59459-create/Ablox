import SwiftUI
import QuartzCore

/// The world from above as one picture, for the map.
///
/// The map used to measure every block of the world from scratch and keep a
/// rectangle for each, every time anything in the world changed — ten times
/// a second in a game whose characters walk — and then drew thousands of
/// rectangles. Now the picture is made again at most every two seconds, from
/// an index kept up to date change by change, and drawn as one image.
@MainActor
final class MapFootprint {
    /// The picture, north up, and the stretch of the world it covers (x and
    /// z in metres).
    let image: CGImage?
    let covers: CGRect
    /// Where most of the world is, for the whole-map view.
    let worldBounds: CGRect

    private init(image: CGImage?, covers: CGRect, worldBounds: CGRect) {
        self.image = image
        self.covers = covers
        self.worldBounds = worldBounds
    }

    /// Made again at most this often while the world keeps changing.
    static let freshness: Double = 2
    /// The picture's longest side, in pixels, and its sharpest.
    static let largestSide: CGFloat = 1024
    static let mostPixelsPerMetre: CGFloat = 4
    /// The highest parts are kept when a world has more than this.
    static let mostParts = 6000

    private static var latest: MapFootprint?
    private static var madeFor: (world: UUID, revision: UInt64, at: Double)?
    private static let indexCache = WorldIndexCache()

    /// The picture of `world`, as made in the last two seconds if there is one.
    static func of(_ world: WorldDocument) -> MapFootprint {
        let now = CACurrentMediaTime()
        if let latest, let made = madeFor, made.world == world.id,
           made.revision == world.blockRevision.value || now - made.at < freshness {
            return latest
        }
        let made = make(world)
        latest = made
        madeFor = (world.id, world.blockRevision.value, now)
        return made
    }

    private struct Plot {
        let rect: CGRect
        let color: ColorRGBA
        let top: Float
    }

    private static func make(_ world: WorldDocument) -> MapFootprint {
        let index = indexCache.index(for: world)
        var plots: [Plot] = []
        var low = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        var high = CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity)
        for (entry, block) in zip(index.entries, world.blocks) where entry.isVisible && block.color.a > 0.15 {
            let b = entry.bounds
            let width = b.max.x - b.min.x, depth = b.max.z - b.min.z
            guard width.isFinite, depth.isFinite, width > 0.05 || depth > 0.05, width < 2000, depth < 2000 else { continue }
            let rect = CGRect(x: CGFloat(b.min.x), y: CGFloat(b.min.z), width: CGFloat(max(width, 0.3)), height: CGFloat(max(depth, 0.3)))
            plots.append(Plot(rect: rect, color: block.color, top: b.max.y))
            // The ground under a whole world says nothing about where it is.
            if width < 400 && depth < 400 {
                low = CGPoint(x: min(low.x, rect.minX), y: min(low.y, rect.minY))
                high = CGPoint(x: max(high.x, rect.maxX), y: max(high.y, rect.maxY))
            }
        }
        // Low things first, so a roof is drawn over the floor under it.
        plots.sort { $0.top < $1.top }
        if plots.count > mostParts { plots.removeFirst(plots.count - mostParts) }

        let worldBounds = low.x.isFinite
            ? CGRect(x: low.x, y: low.y, width: max(20, high.x - low.x), height: max(20, high.y - low.y))
            : CGRect(x: -50, y: -50, width: 100, height: 100)
        // A margin round it, for the small map near the edge.
        let margin = max(60, max(worldBounds.width, worldBounds.height) * 0.5)
        let covers = worldBounds.insetBy(dx: -margin, dy: -margin)
        return MapFootprint(image: draw(plots, covering: covers), covers: covers, worldBounds: worldBounds)
    }

    private static func draw(_ plots: [Plot], covering covers: CGRect) -> CGImage? {
        let perMetre = min(mostPixelsPerMetre, largestSide / max(covers.width, covers.height))
        let width = max(1, Int((covers.width * perMetre).rounded(.up)))
        let height = max(1, Int((covers.height * perMetre).rounded(.up)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // North (−z) at the top of the picture, as on the map.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: perMetre, y: -perMetre)
        context.translateBy(x: -covers.minX, y: -covers.minY)
        for plot in plots {
            context.setFillColor(red: CGFloat(plot.color.r), green: CGFloat(plot.color.g), blue: CGFloat(plot.color.b), alpha: 0.85)
            // At least a pixel across, as the map always drew them.
            let rect = CGRect(x: plot.rect.minX, y: plot.rect.minY,
                              width: max(plot.rect.width, 1 / perMetre), height: max(plot.rect.height, 1 / perMetre))
            context.fill(rect)
        }
        return context.makeImage()
    }
}

/// The compass strip, following the camera a few times a second without
/// the play screen being drawn again (`PlayControls.shownYaw`).
struct CameraCompass: View {
    @ObservedObject var controls: PlayControls

    var body: some View {
        CompassStrip(bearing: Compass.bearing(cameraYaw: controls.shownYaw))
    }
}

/// Whatever turns with the camera — the small map, when the player chose
/// that — following it a few times a second.
struct FollowingBearing<Content: View>: View {
    @ObservedObject var controls: PlayControls
    let content: (Float) -> Content

    var body: some View {
        content(Compass.bearing(cameraYaw: controls.shownYaw))
    }
}
