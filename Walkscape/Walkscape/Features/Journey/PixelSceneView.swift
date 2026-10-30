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
    /// Picks the companion's way of moving (steady, bouncy or floating).
    var companionSpeciesID: String?
    /// Layers scroll and the character steps only while walking.
    var walking = true
    var pixel: CGFloat = Theme.pixel
    /// Horizontal position of the character, 0...1.
    var characterPosition: Double = 0.3
    /// When false the scene is drawn once, e.g. for lists of many scenes.
    var animated = true
    /// Seasonal colours and weather; nil draws the plain scene.
    var season: Season?
    /// A world event happening here today, drawn in the scene.
    var eventSpriteID: String?
    /// Team worlds recolour the biome in the world's palette.
    var tint: WorldTint?
    /// A premium trail drawn behind the walker while walking.
    var trail: TrailEffect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(32, Int((geometry.size.width / pixel).rounded(.up)))
            let height = max(40, Int((geometry.size.height / pixel).rounded(.up)))
            if let images = PixelArtCache.shared.scene(biome, width: width, height: height, season: season, tint: tint) {
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
            if animated && !reduceMotion, let particles = SeasonalParticles.Kind.for(biome: biome, season: season) {
                SeasonalParticles(kind: particles.kind, time: time, density: particles.density, pixel: pixel)
            }
            if let eventSpriteID, let icon = PixelArtCache.shared.item(eventSpriteID) {
                // Bobs gently a little way ahead of the walker.
                let bob = animated && !reduceMotion ? (sin(time * 2) * 1.5).rounded() : 0
                layer(icon, width: 10, height: 10)
                    .offset(x: (CGFloat(width) * 0.68).rounded() * pixel,
                            y: CGFloat(images.layers.footY - 16 + Int(bob)) * pixel)
            }
            if let companionImage, avatarID != nil {
                // Walks just behind the character, each species in its own way.
                let hop = companionOffset(time: time, stepping: stepping)
                layer(companionImage, width: CompanionSprites.canvasSize, height: CompanionSprites.canvasSize)
                    .offset(x: ((CGFloat(width) * characterPosition).rounded() - CGFloat(CompanionSprites.canvasSize) + 2) * pixel,
                            y: CGFloat(images.layers.footY - CompanionSprites.canvasSize + 1 + hop) * pixel)
            }
            if let trail, stepping, avatarID != nil {
                TrailLayer(effect: trail, time: time, pixel: pixel,
                           origin: CGPoint(x: (CGFloat(width) * characterPosition).rounded() * pixel,
                                           y: CGFloat(images.layers.footY - 4) * pixel))
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

    /// Mossling plods, Emberfox bounces (and hops on the spot when resting),
    /// Moonmoth floats up and down all the time.
    private func companionOffset(time: Double, stepping: Bool) -> Int {
        let moving = animated && !reduceMotion
        switch companionSpeciesID {
        case "emberfox":
            if stepping { return Int(time * 6) % 2 == 0 ? -2 : 0 }
            return moving && Int(time * 2) % 6 == 0 ? -2 : 0
        case "moonmoth":
            return moving ? Int((sin(time * 2.2) * 1.6 - 2).rounded()) : -2
        default:
            return stepping && Int(time * 2) % 2 == 0 ? -1 : 0
        }
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

/// Sparkles, petals or stardust drifting behind the walker.
private struct TrailLayer: View {
    let effect: TrailEffect
    let time: Double
    let pixel: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            for index in 0..<10 {
                // Each particle drifts back and fades over a second, then restarts.
                let age = (time * 1.2 + Double(index) / 10).truncatingRemainder(dividingBy: 1)
                let x = origin.x - age * 40 * pixel / 3 + sin(Double(index) * 1.7) * 2 * pixel
                let y = origin.y - age * 10 * pixel / 3 + cos(time * 3 + Double(index)) * pixel
                let color = Color(hex: effect.colors[index % effect.colors.count]).opacity(1 - age)
                let rect = CGRect(x: (x / pixel).rounded() * pixel, y: (y / pixel).rounded() * pixel, width: pixel, height: pixel)
                context.fill(Path(rect), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Pixel weather: snow, falling leaves, petals or fireflies.
private struct SeasonalParticles: View {
    enum Kind {
        case snow, leaves, petals, fireflies

        /// What falls in this biome and season, and how much.
        static func `for`(biome: Biome, season: Season?) -> (kind: Kind, density: Int)? {
            if biome == .crystalCaves { return nil }
            if [Biome.snowyRidge, .summit, .starlightPass].contains(biome) {
                return (.snow, biome == .snowyRidge || season == .winter ? 40 : 12)
            }
            if biome == .fireflyMarsh { return (.fireflies, 18) }
            switch season {
            case .winter: return [.redCanyon, .sandyShore, .hotSprings].contains(biome) ? nil : (.snow, 24)
            case .autumn: return (.leaves, biome == .autumnWoods ? 22 : 12)
            case .spring: return (.petals, biome == .blossomOrchard ? 22 : 10)
            case .summer: return [.meadow, .lakeside, .riverside, .lavenderFields].contains(biome) ? (.fireflies, 8) : nil
            case nil: return biome == .autumnWoods ? (.leaves, 14) : biome == .blossomOrchard ? (.petals, 14) : nil
            }
        }
    }

    let kind: Kind
    let time: Double
    let density: Int
    let pixel: CGFloat

    var body: some View {
        Canvas { context, size in
            for index in 0..<density {
                // Deterministic pseudo-random lane per particle.
                let seed = Double((index * 7_919) % 1_000) / 1_000
                let (speed, sway, color): (Double, Double, Color) = {
                    switch kind {
                    case .snow: return (6 + seed * 8, 6, .white.opacity(0.85))
                    case .leaves: return (5 + seed * 5, 14, [Color(hex: 0xD9822B), Color(hex: 0xB5452A), Color(hex: 0xE0B040)][index % 3])
                    case .petals: return (4 + seed * 4, 12, index % 3 == 0 ? .white.opacity(0.9) : Color(hex: 0xF4B6C8))
                    case .fireflies: return (0, 10, Color(hex: 0xFFE59A).opacity(0.4 + 0.6 * abs(sin(time * 2 + Double(index)))))
                    }
                }()
                let x = (seed * size.width + sin(time * 0.8 + Double(index)) * sway)
                    .truncatingRemainder(dividingBy: size.width)
                let y: Double = kind == .fireflies
                    ? size.height * (0.45 + 0.35 * seed) + sin(time * 1.3 + Double(index) * 2) * 8
                    : (time * speed * pixel + Double(index * 37)).truncatingRemainder(dividingBy: size.height)
                let side = kind == .leaves && index % 2 == 0 ? 2 * pixel : pixel
                let snapped = CGRect(x: (x / pixel).rounded() * pixel, y: (y / pixel).rounded() * pixel, width: side, height: pixel)
                context.fill(Path(snapped), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}
