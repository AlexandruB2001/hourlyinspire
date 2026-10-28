import CoreGraphics
import PixelArt
import SwiftUI
import UIKit
import WalkscapeDomain

extension PixelCanvas {
    /// A non-interpolated sRGB image of the canvas (straight alpha).
    func makeCGImage() -> CGImage? {
        let data = Data(rgbaBytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Memoises rendered pixel art. Rendering is cheap, but lists redraw often.
@MainActor
final class PixelArtCache {
    static let shared = PixelArtCache()

    private var images: [String: CGImage] = [:]
    private var scenes: [String: SceneImages] = [:]

    struct SceneImages {
        let layers: SceneLayers
        let sky: CGImage
        let clouds: CGImage
        let far: CGImage
        let mid: CGImage
        let ground: CGImage
    }

    /// Looks for an artist-supplied asset named `key` first (see docs/ART_PIPELINE.md),
    /// falling back to the procedural art.
    func image(_ key: String, render: () -> PixelCanvas) -> CGImage? {
        if let cached = images[key] { return cached }
        let image = UIImage(named: key)?.cgImage ?? render().makeCGImage()
        images[key] = image
        return image
    }

    func scene(_ biome: Biome, width: Int, height: Int) -> SceneImages? {
        let key = "\(biome.rawValue)-\(width)x\(height)"
        if let cached = scenes[key] { return cached }
        let layers = SceneRenderer.render(biome, width: width, height: height)
        guard let sky = layers.sky.makeCGImage(), let clouds = layers.clouds.makeCGImage(),
              let far = layers.far.makeCGImage(), let mid = layers.mid.makeCGImage(),
              let ground = layers.ground.makeCGImage() else { return nil }
        if scenes.count > 24 { scenes.removeAll() }
        let images = SceneImages(layers: layers, sky: sky, clouds: clouds, far: far, mid: mid, ground: ground)
        scenes[key] = images
        return images
    }

    func characterFrame(_ frame: Int, avatarID: String, walking: Bool) -> CGImage? {
        let index = ((frame % CharacterSprites.walkFrameCount) + CharacterSprites.walkFrameCount) % CharacterSprites.walkFrameCount
        let key = walking ? "character_\(avatarID)_walk_\(index)" : "character_\(avatarID)_idle"
        return image(key) {
            walking ? CharacterSprites.walkFrame(index, avatarID: avatarID) : CharacterSprites.idleFrame(avatarID: avatarID)
        }
    }

    /// A frame wearing shop items, `CharacterSprites.outfittedHeight` tall.
    func characterFrame(_ frame: Int, avatarID: String, outfit: [String], walking: Bool) -> CGImage? {
        let index = ((frame % CharacterSprites.walkFrameCount) + CharacterSprites.walkFrameCount) % CharacterSprites.walkFrameCount
        let look = ([avatarID] + outfit).joined(separator: "+")
        let key = walking ? "outfit_\(look)_walk_\(index)" : "outfit_\(look)_idle"
        return image(key) {
            walking ? CharacterSprites.walkFrame(index, avatarID: avatarID, outfit: outfit)
                : CharacterSprites.idleFrame(avatarID: avatarID, outfit: outfit)
        }
    }

    /// A companion as it looks after `kilometres` walked together.
    func companion(_ speciesID: String, kilometres: Int) -> CGImage? {
        let growth = CompanionGrowth(kilometres: kilometres)
        // Keyed by what's actually drawn, so 200 km and 300 km share an image.
        let detail = growth.stage == .elder ? 0 : min(growth.kilometresIntoStage, 60)
        return image("companion_\(speciesID)_\(growth.stage.rawValue)_\(detail)") {
            CompanionSprites.render(speciesID: speciesID, growth: growth)
        }
    }

    /// A companion at the start of `stage` with all of that stage's details.
    func companion(_ speciesID: String, stage: CompanionGrowth.Stage) -> CGImage? {
        let km = stage.next.map { $0.startKilometres - 1 } ?? stage.startKilometres
        return companion(speciesID, kilometres: km)
    }

    func portrait(avatarID: String) -> CGImage? {
        image("portrait_\(avatarID)") { CharacterSprites.portrait(avatarID: avatarID) }
    }

    func item(_ spriteID: String) -> CGImage? {
        image("item_\(spriteID)") { ItemSprites.render(spriteID) }
    }

    /// A still frame of a biome rendered at exactly `width`x`height` art pixels.
    func thumbnail(_ biome: Biome, width: Int, height: Int) -> CGImage? {
        image("thumb_\(biome.rawValue)_\(width)x\(height)") { SceneRenderer.thumbnail(biome, width: width, height: height) }
    }
}

/// Displays a pixel image scaled by whole logical pixels.
struct PixelImageView: View {
    let image: CGImage?
    var pixel: CGFloat = Theme.pixel

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: CGFloat(image.width) * pixel, height: CGFloat(image.height) * pixel)
        } else {
            Color.clear.frame(width: 16 * pixel, height: 16 * pixel)
        }
    }
}

/// A character portrait in a small framed tile.
struct AvatarPortrait: View {
    let avatarID: String
    var size: CGFloat = 36
    var ring: Color = Theme.Palette.ink

    var body: some View {
        let image = PixelArtCache.shared.portrait(avatarID: avatarID)
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.skyMuted)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.08)
                    .offset(y: size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(ring, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

/// An item or achievement icon.
struct ItemIcon: View {
    let spriteID: String
    var pixel: CGFloat = 3
    var locked = false

    var body: some View {
        PixelImageView(image: PixelArtCache.shared.item(spriteID), pixel: pixel)
            .saturation(locked ? 0 : 1)
            .opacity(locked ? 0.35 : 1)
            .accessibilityHidden(true)
    }
}

/// The walking adventurer, animated with the shared walk cycle.
struct WalkingCharacter: View {
    let avatarID: String
    /// Shop items to wear. Nil draws the plain walker (as friends see it).
    var outfit: [String]?
    var walking = true
    var pixel: CGFloat = Theme.pixel
    /// Offsets the cycle so a crowd doesn't step in unison.
    var phase: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 8, paused: !walking || reduceMotion)) { context in
            let frame = Int((context.date.timeIntervalSinceReferenceDate + phase) * 8)
            let moving = walking && !reduceMotion
            let image = outfit.map { PixelArtCache.shared.characterFrame(frame, avatarID: avatarID, outfit: $0, walking: moving) }
                ?? PixelArtCache.shared.characterFrame(frame, avatarID: avatarID, walking: moving)
            PixelImageView(image: image, pixel: pixel)
        }
        .accessibilityHidden(true)
    }
}

/// Icon for a journal entry: an item sprite, a zone thumbnail ("zone:<biome>")
/// or a companion ("companion:<species>:<stage>").
struct JournalIcon: View {
    let iconID: String
    var size: CGFloat = 36

    var body: some View {
        let parts = iconID.split(separator: ":").map(String.init)
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised)
            if parts.first == "zone", parts.count == 2, let biome = Biome(rawValue: parts[1]) {
                PixelImageView(image: PixelArtCache.shared.thumbnail(biome, width: 24, height: 24), pixel: size / 24)
            } else if parts.first == "companion", parts.count == 3,
                      let stage = Int(parts[2]).flatMap(CompanionGrowth.Stage.init(rawValue:)) {
                PixelImageView(image: PixelArtCache.shared.companion(parts[1], stage: stage),
                               pixel: (size - 4) / CGFloat(CompanionSprites.canvasSize))
            } else {
                ItemIcon(spriteID: iconID, pixel: (size - 6) / 10)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
        .accessibilityHidden(true)
    }
}
