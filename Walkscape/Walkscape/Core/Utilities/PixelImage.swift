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
    var walking = true
    var pixel: CGFloat = Theme.pixel
    /// Offsets the cycle so a crowd doesn't step in unison.
    var phase: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 8, paused: !walking || reduceMotion)) { context in
            let frame = Int((context.date.timeIntervalSinceReferenceDate + phase) * 8)
            PixelImageView(image: PixelArtCache.shared.characterFrame(frame, avatarID: avatarID,
                                                                      walking: walking && !reduceMotion),
                           pixel: pixel)
        }
        .accessibilityHidden(true)
    }
}
