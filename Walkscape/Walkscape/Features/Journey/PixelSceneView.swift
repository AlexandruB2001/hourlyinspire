import PixelArt
import SwiftUI
import WalkscapeDomain

/// An animated parallax pixel landscape for a biome, optionally with the
/// player's character walking along the path.
///
/// The scene is rendered at the view's size divided by `pixel`, so every
/// art pixel is exactly `pixel` points and stays crisp at any size.
struct PixelSceneView: View {
    let biome: Biome
    var avatarID: String?
    /// Shop items the character wears; nil for the plain walker.
    var outfit: [String]?
    /// The companion trotting behind the walker.
    var companionImage: CGImage?
    /// Layers scroll and the character steps only while walking.
    var walking = true
    var pixel: CGFloat = Theme.pixel
    /// Horizontal position of the character, 0...1.
    var characterPosition: Double = 0.3
    /// When false the scene is drawn once, e.g. for lists of many scenes.
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(32, Int((geometry.size.width / pixel).rounded(.up)))
            let height = max(40, Int((geometry.size.height / pixel).rounded(.up)))
            if let images = PixelArtCache.shared.scene(biome, width: width, height: height) {
                let frames = characterFrames()
                if animated && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        frame(images, frames: frames, width: width, height: height,
                              time: context.date.timeIntervalSinceReferenceDate, size: geometry.size)
                    }
                } else {
                    frame(images, frames: frames, width: width, height: height, time: 0, size: geometry.size)
                }
            } else {
                Theme.Palette.forest
            }
        }
        .accessibilityHidden(true)
    }

    private func frame(_ images: PixelArtCache.SceneImages, frames: [CGImage]?, width: Int, height: Int,
                       time: Double, size: CGSize) -> some View {
        let speeds = SceneLayers.scrollSpeeds
        let move = walking ? 1.0 : 0.0
        let stepping = walking && animated && !reduceMotion
        return ZStack(alignment: .topLeading) {
            layer(images.sky, width: width, height: height)
            tiled(images.clouds, offset: time * speeds.clouds, width: width, height: height)
            tiled(images.far, offset: time * speeds.far * move, width: width, height: height)
            tiled(images.mid, offset: time * speeds.mid * move, width: width, height: height)
            tiled(images.ground, offset: time * speeds.ground * move, width: width, height: height)
            if animated && !reduceMotion && [Biome.snowyRidge, .summit, .starlightPass].contains(biome) {
                SnowfallLayer(time: time, density: biome == .snowyRidge ? 40 : 12, pixel: pixel)
            }
            if let companionImage, avatarID != nil {
                // Walks just behind the character and hops along while walking.
                let hop = stepping && Int(time * 4) % 2 == 0 ? -1 : 0
                layer(companionImage, width: CompanionSprites.canvasSize, height: CompanionSprites.canvasSize)
                    .offset(x: ((CGFloat(width) * characterPosition).rounded() - CGFloat(CompanionSprites.canvasSize) + 2) * pixel,
                            y: CGFloat(images.layers.footY - CompanionSprites.canvasSize + 1 + hop) * pixel)
            }
            if let frames, let idle = frames.last {
                let walkCount = frames.count - 1
                let image = stepping && walkCount > 0 ? frames[Int(time * 8) % walkCount] : idle
                let characterHeight = outfit == nil ? CharacterSprites.height : CharacterSprites.outfittedHeight
                layer(image, width: CharacterSprites.width, height: characterHeight)
                    .offset(x: (CGFloat(width) * characterPosition).rounded() * pixel,
                            y: CGFloat(images.layers.footY - characterHeight + 1) * pixel)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    /// Walk frames followed by the idle frame.
    private func characterFrames() -> [CGImage]? {
        guard let avatarID else { return nil }
        let cache = PixelArtCache.shared
        func frame(_ index: Int, walking: Bool) -> CGImage? {
            if let outfit { return cache.characterFrame(index, avatarID: avatarID, outfit: outfit, walking: walking) }
            return cache.characterFrame(index, avatarID: avatarID, walking: walking)
        }
        let walk = (0..<CharacterSprites.walkFrameCount).compactMap { frame($0, walking: true) }
        let idle = frame(0, walking: false)
        return walk + [idle].compactMap { $0 }
    }

    private func layer(_ image: CGImage, width: Int, height: Int) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: CGFloat(width) * pixel, height: CGFloat(height) * pixel)
    }

    /// Two copies side by side, shifted by a whole number of art pixels.
    private func tiled(_ image: CGImage, offset: Double, width: Int, height: Int) -> some View {
        let shift = Int(offset.rounded(.down)) % width
        return HStack(spacing: 0) {
            layer(image, width: width, height: height)
            layer(image, width: width, height: height)
        }
        .offset(x: -CGFloat(shift) * pixel)
    }
}

/// Gentle pixel snow for cold biomes.
private struct SnowfallLayer: View {
    let time: Double
    let density: Int
    let pixel: CGFloat

    var body: some View {
        Canvas { context, size in
            for index in 0..<density {
                // Deterministic pseudo-random lane per flake.
                let seed = Double((index * 7_919) % 1_000) / 1_000
                let speed = 6 + seed * 8
                let x = (seed * size.width + sin(time * 0.8 + Double(index)) * 6)
                    .truncatingRemainder(dividingBy: size.width)
                let y = (time * speed * pixel + Double(index * 37)).truncatingRemainder(dividingBy: size.height)
                let snapped = CGRect(x: (x / pixel).rounded() * pixel, y: (y / pixel).rounded() * pixel,
                                     width: pixel, height: pixel)
                context.fill(Path(snapped), with: .color(.white.opacity(0.85)))
            }
        }
        .allowsHitTesting(false)
    }
}
