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
    /// A trail drawn behind the walker (a contrail, or a premium trail).
    var trail: TrailEffect?
    /// Tapping the walker or the companion makes them hop.
    var tappable = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When each last hopped (seconds since the reference date, as `time`).
    @State private var walkerHopStart = -10.0
    @State private var companionHopStart = -10.0
    @State private var hops = 0

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
        .sensoryFeedback(.impact(weight: .light), trigger: hops)
    }

    /// A quick hop: up 7 art pixels and back down in half a second.
    private func hopOffset(since start: Double, time: Double) -> Int {
        let t = time - start
        guard t >= 0, t < 0.5 else { return 0 }
        return -Int((sin(.pi * t / 0.5) * 7).rounded())
    }

    /// An invisible tap target over a sprite, a little larger than it.
    private func hopTarget(x: CGFloat, y: CGFloat, width: Int, height: Int, hop: @escaping () -> Void) -> some View {
        let margin: CGFloat = 8
        return Color.clear
            .contentShape(Rectangle())
            .frame(width: CGFloat(width) * pixel + 2 * margin, height: CGFloat(height) * pixel + 2 * margin)
            .offset(x: x * pixel - margin, y: y * pixel - margin)
            .onTapGesture {
                hop()
                hops += 1
            }
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
            let characterX = (CGFloat(width) * characterPosition).rounded()
            let companionX = characterX - CGFloat(CompanionSprites.canvasSize) + 2
            let companionY = images.layers.footY - CompanionSprites.canvasSize + 1
            if let trail, animated, !reduceMotion, avatarID != nil {
                TrailLayer(effect: trail, time: time, pixel: pixel,
                           origin: CGPoint(x: characterX * pixel, y: CGFloat(images.layers.footY - 4) * pixel))
            }
            if let companionImage, avatarID != nil {
                // Walks just behind the character, each species in its own way.
                let hop = companionOffset(time: time, stepping: stepping) + hopOffset(since: companionHopStart, time: time)
                layer(companionImage, width: CompanionSprites.canvasSize, height: CompanionSprites.canvasSize)
                    .offset(x: companionX * pixel, y: CGFloat(companionY + hop) * pixel)
            }
            let characterHeight = outfit == nil ? CharacterSprites.height : CharacterSprites.outfittedHeight
            let characterY = images.layers.footY - characterHeight + 1
            if let frames, let idle = frames.last {
                let walkCount = frames.count - 1
                let image = stepping && walkCount > 0 ? frames[Int(time * 8) % walkCount] : idle
                layer(image, width: CharacterSprites.width, height: characterHeight)
                    .offset(x: characterX * pixel, y: CGFloat(characterY + hopOffset(since: walkerHopStart, time: time)) * pixel)
            }
            if tappable, animated, !reduceMotion, avatarID != nil {
                if companionImage != nil {
                    hopTarget(x: companionX, y: CGFloat(companionY), width: CompanionSprites.canvasSize,
                              height: CompanionSprites.canvasSize) { companionHopStart = Date().timeIntervalSinceReferenceDate }
                }
                hopTarget(x: characterX, y: CGFloat(characterY), width: CharacterSprites.width,
                          height: characterHeight) { walkerHopStart = Date().timeIntervalSinceReferenceDate }
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

/// A trail behind the walker: sparkles, a rainbow ribbon, comet embers,
/// stardust or bubbles. `origin` is the walker's back at hip height; the
/// trail streams out to the left. Everything snaps to whole art pixels.
struct TrailLayer: View {
    let effect: TrailEffect
    let time: Double
    let pixel: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            /// Fills one art pixel `dx`, `dy` art pixels from the origin.
            func dot(_ dx: Double, _ dy: Double, _ color: UInt32, _ opacity: Double, size: Int = 1) {
                guard opacity > 0.02 else { return }
                let x = (origin.x / pixel + dx).rounded() * pixel
                let y = (origin.y / pixel + dy).rounded() * pixel
                let side = CGFloat(size) * pixel
                context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(Color(hex: color).opacity(opacity)))
            }
            let colors = effect.colors
            switch effect.style {
            case .sparkles:
                for index in 0..<10 {
                    // Each particle drifts back and fades over a second, then restarts.
                    let age = (time * 1.2 + Double(index) / 10).truncatingRemainder(dividingBy: 1)
                    dot(-age * 13 + sin(Double(index) * 1.7) * 2, -age * 3 + cos(time * 3 + Double(index)),
                        colors[index % colors.count], 1 - age)
                }
            case .ribbon:
                // One stripe per colour, waving more the further back it goes.
                let length = 26
                for (band, color) in colors.enumerated() {
                    for step in 1...length {
                        let back = Double(step)
                        let wave = sin(time * 7 - back * 0.32) * 1.8 * back / Double(length)
                        dot(-back, Double(band) - Double(colors.count) + 1 + wave, color,
                            0.95 * (1 - back / Double(length + 2)))
                    }
                }
            case .embers:
                for index in 0..<16 {
                    let seed = Double((index * 7_919) % 1_000) / 1_000
                    let age = (time * 1.5 + seed).truncatingRemainder(dividingBy: 1)
                    // Thrown back and up, then falling, cooling from white-yellow to red.
                    let dx = -age * (12 + seed * 10)
                    let dy = -3 - seed * 4 + age * age * 10 + sin(time * 9 + Double(index)) * 0.5
                    let flicker = sin(time * 23 + Double(index) * 3) > -0.6 ? 1.0 : 0.3
                    let color = colors[min(colors.count - 1, Int(age * Double(colors.count)))]
                    dot(dx, dy, color, (1 - age) * flicker, size: age < 0.25 && index % 3 == 0 ? 2 : 1)
                }
            case .stardust:
                for index in 0..<18 {
                    let seed = Double((index * 6_271) % 1_000) / 1_000
                    let age = (time * 0.55 + seed).truncatingRemainder(dividingBy: 1)
                    let dx = -2 - age * 28 + sin(time + Double(index)) * 1.5
                    let dy = -6 + seed * 9 - age * 3 + cos(time * 1.3 + Double(index) * 2)
                    let twinkle = 0.5 + 0.5 * sin(time * 6 + Double(index) * 2.3)
                    let color = colors[index % colors.count]
                    let opacity = (1 - age) * (0.35 + 0.65 * twinkle)
                    dot(dx, dy, color, opacity)
                    if twinkle > 0.85 {
                        // The brightest grains flash into little crosses.
                        for (cx, cy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                            dot(dx + cx, dy + cy, color, opacity * 0.6)
                        }
                    }
                }
            case .bubbles:
                for index in 0..<8 {
                    let seed = Double((index * 4_513) % 1_000) / 1_000
                    let age = (time * 0.6 + Double(index) / 8).truncatingRemainder(dividingBy: 1)
                    let dx = -3 - age * 16 - seed * 4 + sin(time * 3 + Double(index)) * 1.2
                    let dy = -2 - age * 14 + seed * 2
                    let color = colors[index % colors.count]
                    let opacity = age > 0.85 ? (1 - age) / 0.15 : 0.9
                    if index % 3 == 0 {
                        dot(dx, dy, color, opacity)
                    } else {
                        // A ring with a shine in its corner.
                        for (cx, cy) in [(0.0, -1.0), (-1.0, 0.0), (1.0, 0.0), (0.0, 1.0)] {
                            dot(dx + cx, dy + cy, color, opacity * 0.85)
                        }
                        dot(dx - 1, dy - 1, 0xFFFFFF, opacity * 0.5)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The walker standing with a trail behind it, for the Shop and the Mystery
/// Box reveal.
struct TrailPreview: View {
    let effect: TrailEffect
    let avatarID: String?
    var pixel: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = CGFloat(CharacterSprites.width) * pixel
            let height = CGFloat(CharacterSprites.outfittedHeight) * pixel
            let x = ((geometry.size.width * 0.62 - width / 2) / pixel).rounded() * pixel
            let y = ((geometry.size.height - height) / 2 / pixel).rounded() * pixel
            let origin = CGPoint(x: x, y: y + height - 4 * pixel)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                ZStack(alignment: .topLeading) {
                    TrailLayer(effect: effect, time: reduceMotion ? 0.4 : context.date.timeIntervalSinceReferenceDate,
                               pixel: pixel, origin: origin)
                    if let avatarID,
                       let image = PixelArtCache.shared.characterFrame(0, avatarID: avatarID, outfit: [], walking: false) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: width, height: height)
                            .offset(x: x, y: y)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .accessibilityHidden(true)
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
