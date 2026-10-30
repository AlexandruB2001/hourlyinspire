import Foundation
import WalkscapeDomain

/// The parallax layers of one zone's scene. Every layer except `sky` tiles
/// horizontally (x wraps at `width`), so the app can scroll them forever.
public struct SceneLayers: Hashable, Sendable {
    public let biome: Biome
    public let width: Int
    public let height: Int
    public let sky: PixelCanvas
    public let clouds: PixelCanvas
    public let far: PixelCanvas
    public let mid: PixelCanvas
    public let ground: PixelCanvas
    /// y of the walking surface; character feet sit on this row.
    public let footY: Int

    /// Suggested scroll speeds in pixels per second while walking.
    public static let scrollSpeeds: (clouds: Double, far: Double, mid: Double, ground: Double) = (1.5, 2, 5, 14)

    /// All layers flattened, each shifted by `offsets` (for previews/thumbnails).
    public func composite(cloudOffset: Int = 0, farOffset: Int = 0, midOffset: Int = 0, groundOffset: Int = 0) -> PixelCanvas {
        var canvas = sky
        for (layer, offset) in [(clouds, cloudOffset), (far, farOffset), (mid, midOffset), (ground, groundOffset)] {
            for y in 0..<height {
                for x in 0..<width { canvas.plot(x, y, layer[x + offset, y]) }
            }
        }
        return canvas
    }
}

/// Procedurally paints cozy pixel landscapes for each biome.
///
/// Output is deterministic for a given biome and size. Wave shapes use whole
/// numbers of cycles across the width and decorations wrap, so each layer
/// tiles seamlessly.
public enum SceneRenderer {
    public static func render(_ biome: Biome, width: Int = 160, height: Int = 100, season: Season? = nil,
                              tint: WorldTint? = nil) -> SceneLayers {
        var painter = ScenePainter(biome: biome, width: max(24, width), height: max(24, height))
        var layers = painter.paint()
        if let season { layers = SeasonalPass.apply(layers, season: season) }
        if let tint, !biome.isTeamWorld { layers = WorldTintPass.apply(layers, tint: tint) }
        return layers
    }

    /// A single flattened frame, e.g. for World screen thumbnails.
    public static func thumbnail(_ biome: Biome, width: Int = 96, height: Int = 56) -> PixelCanvas {
        render(biome, width: width, height: height).composite()
    }
}

// MARK: - Random numbers

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    /// Like `int(_:)` but tolerates `upper < lower` (returns `lower`), which
    /// happens for tiny thumbnail sizes.
    mutating func int(_ lower: Int, _ upper: Int) -> Int {
        upper <= lower ? lower : int(lower...upper)
    }

    mutating func double() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func chance(_ p: Double) -> Bool { double() < p }
}

// MARK: - Painter

struct ScenePainter {
    let biome: Biome
    let width: Int
    let height: Int
    var rng: SplitMix64

    init(biome: Biome, width: Int, height: Int) {
        self.biome = biome
        self.width = width
        self.height = height
        var seed: UInt64 = 1469598103934665603
        for byte in biome.rawValue.utf8 { seed = (seed ^ UInt64(byte)) &* 1099511628211 }
        rng = SplitMix64(seed: seed)
    }

    func layer() -> PixelCanvas { PixelCanvas(width: width, height: height, wrapsHorizontally: true) }

    /// Fraction of height -> row.
    func y(_ fraction: Double) -> Int { Int((Double(height) * fraction).rounded()) }

    /// Sum of sines with whole cycles across the width, so it tiles.
    func wave(_ x: Int, _ terms: [(cycles: Int, amplitude: Double, phase: Double)]) -> Double {
        terms.reduce(0) { sum, term in
            sum + term.amplitude * sin(2 * .pi * Double(term.cycles) * Double(x) / Double(width) + term.phase)
        }
    }

    mutating func terms(_ spec: [(Int, Double)]) -> [(cycles: Int, amplitude: Double, phase: Double)] {
        spec.map { ($0.0, $0.1, rng.double() * 2 * .pi) }
    }

    /// Evenly spread positions with jitter; wraps cleanly.
    mutating func positions(count: Int, jitter: Int) -> [Int] {
        guard count > 0 else { return [] }
        let step = Double(width) / Double(count)
        return (0..<count).map { Int(Double($0) * step) + rng.int(-jitter...jitter) }
    }

    mutating func paint() -> SceneLayers {
        let style = BiomeStyle.style(for: biome)
        let footY = y(0.83)
        var sky = PixelCanvas(width: width, height: height)
        paintSky(&sky, style: style)
        var clouds = layer()
        if style.clouds { paintClouds(&clouds, color: style.cloud, shade: style.cloudShade) }
        var far = layer()
        var mid = layer()
        var ground = layer()

        switch biome {
        case .meadow: paintMeadow(&far, &mid, &ground, style, footY)
        case .riverside: paintRiverside(&far, &mid, &ground, style, footY)
        case .pineForest: paintPineForest(&far, &mid, &ground, style, footY)
        case .rollingHills: paintRollingHills(&far, &mid, &ground, style, footY)
        case .lakeside: paintLakeside(&far, &mid, &ground, style, footY)
        case .village: paintVillage(&far, &mid, &ground, style, footY)
        case .crystalCaves: paintCaves(&sky, &far, &mid, &ground, style, footY)
        case .snowyRidge: paintSnowyRidge(&far, &mid, &ground, style, footY)
        case .cloudForest: paintCloudForest(&far, &mid, &ground, style, footY)
        case .summit: paintSummit(&far, &mid, &ground, style, footY)
        case .starlightPass: paintStarlightPass(&clouds, &far, &mid, &ground, style, footY)
        case .hotSprings: paintHotSprings(&far, &mid, &ground, style, footY)
        case .autumnWoods: paintAutumnWoods(&far, &mid, &ground, style, footY)
        case .bambooGrove: paintBambooGrove(&far, &mid, &ground, style, footY)
        case .blossomOrchard: paintBlossomOrchard(&far, &mid, &ground, style, footY)
        case .lavenderFields: paintLavenderFields(&far, &mid, &ground, style, footY)
        case .redCanyon: paintRedCanyon(&far, &mid, &ground, style, footY)
        case .fireflyMarsh: paintFireflyMarsh(&far, &mid, &ground, style, footY)
        case .sandyShore: paintSandyShore(&far, &mid, &ground, style, footY)
        case .lighthousePoint: paintLighthousePoint(&far, &mid, &ground, style, footY)
        case .enchantedForest: paintEnchantedForest(&far, &mid, &ground, style, footY)
        case .crystalPalace: paintCrystalPalace(&far, &mid, &ground, style, footY)
        case .desertRuins: paintDesertRuins(&far, &mid, &ground, style, footY)
        case .skyIslands: paintSkyIslands(&far, &mid, &ground, style, footY)
        case .ancientCity: paintAncientCity(&far, &mid, &ground, style, footY)
        }
        return SceneLayers(biome: biome, width: width, height: height, sky: sky, clouds: clouds, far: far,
                           mid: mid, ground: ground, footY: footY)
    }

    // MARK: Sky

    mutating func paintSky(_ canvas: inout PixelCanvas, style: BiomeStyle) {
        let stops = style.sky
        let bandCount = stops.count
        let horizon = y(0.75)
        for row in 0..<height {
            let t = min(1, Double(row) / Double(max(1, horizon)))
            let position = t * Double(bandCount - 1)
            let index = min(bandCount - 2, Int(position))
            let local = position - Double(index)
            for x in 0..<width {
                // Ordered dither between neighbouring bands for a soft pixel gradient.
                let threshold = [[0.2, 0.6], [0.8, 0.4]][row % 2][x % 2]
                let color = local > 0.75 + (threshold - 0.5) * 0.4 ? stops[index + 1] : stops[index]
                canvas.plot(x, row, color)
            }
        }
        if let sun = style.sun {
            let cx = Int(Double(width) * 0.78)
            let cy = y(0.2)
            let r = max(3, height / 14)
            canvas.fillEllipse(cx: cx, cy: cy, rx: r + 3, ry: r + 3, sun.withAlpha(50))
            canvas.fillEllipse(cx: cx, cy: cy, rx: r + 1, ry: r + 1, sun.withAlpha(90))
            canvas.fillEllipse(cx: cx, cy: cy, rx: r, ry: r, sun)
        }
        if style.stars {
            for _ in 0..<(width * height / 220) {
                let x = rng.int(0...(width - 1))
                let yy = rng.int(0, y(0.45))
                canvas.plot(x, yy, PixelColor(0xFFF6E0, alpha: UInt8(rng.int(120...230))))
            }
        }
    }

    mutating func paintClouds(_ canvas: inout PixelCanvas, color: PixelColor, shade: PixelColor) {
        for x in positions(count: max(2, width / 55), jitter: width / 12) {
            let cy = rng.int(y(0.1), y(0.32))
            let w = rng.int(8...14)
            cloud(&canvas, x: x, y: cy, width: w, color: color, shade: shade)
        }
    }

    func cloud(_ canvas: inout PixelCanvas, x: Int, y: Int, width w: Int, color: PixelColor, shade: PixelColor) {
        canvas.fillEllipse(cx: x, cy: y + 1, rx: w, ry: 2, shade)
        canvas.fillEllipse(cx: x - w / 3, cy: y, rx: w / 2, ry: 3, color)
        canvas.fillEllipse(cx: x + w / 4, cy: y - 1, rx: w / 2, ry: 4, color)
        canvas.hline(x: x - w + 1, y: y + 2, length: w * 2 - 1, color)
    }

    // MARK: Shapes

    /// A filled ridge whose top follows `wave` around `base`, with a lighter rim.
    mutating func ridge(_ canvas: inout PixelCanvas, base: Int, spec: [(Int, Double)], fill: PixelColor,
                        rim: PixelColor? = nil, bottom: Int? = nil) -> [Int] {
        let t = terms(spec)
        var tops: [Int] = []
        for x in 0..<width {
            let top = base + Int(wave(x, t).rounded())
            tops.append(top)
            canvas.vline(x: x, y: top, length: (bottom ?? height) - top, fill)
            if let rim { canvas.plot(x, top, rim) }
        }
        return tops
    }

    func pine(_ canvas: inout PixelCanvas, x: Int, base: Int, height h: Int, dark: PixelColor, light: PixelColor,
              trunk: PixelColor? = nil, snow: PixelColor? = nil) {
        if let trunk { canvas.fillRect(x: x - 1, y: base - 2, width: 2, height: 3, trunk) }
        let top = base - h
        for row in 0..<(h - 1) {
            // Stepped triangle: widens in tiers for a classic pixel pine.
            let tier = row % max(3, h / 4)
            let half = max(1, (row * 5) / (h * 2) + tier / 2)
            let yy = top + row
            canvas.hline(x: x - half, y: yy, length: half * 2, dark)
            canvas.hline(x: x - half, y: yy, length: max(1, half - 1), light)
            if let snow, tier == 0, row > 0 { canvas.hline(x: x - half + 1, y: yy, length: max(1, half), snow) }
        }
        canvas.plot(x - 1, top - 1, dark)
        canvas.plot(x, top - 1, dark)
        if let snow { canvas.plot(x - 1, top - 1, snow) }
    }

    func roundTree(_ canvas: inout PixelCanvas, x: Int, base: Int, radius r: Int, dark: PixelColor, light: PixelColor,
                   trunk: PixelColor) {
        canvas.fillRect(x: x - 1, y: base - r - 1, width: 2, height: r + 1, trunk)
        canvas.fillEllipse(cx: x, cy: base - r * 2, rx: r, ry: r, dark)
        canvas.fillEllipse(cx: x - 1, cy: base - r * 2 - 1, rx: max(1, r - 2), ry: max(1, r - 2), light)
    }

    func bush(_ canvas: inout PixelCanvas, x: Int, base: Int, radius r: Int, dark: PixelColor, light: PixelColor) {
        canvas.fillEllipse(cx: x, cy: base - r / 2, rx: r, ry: max(1, r / 2 + 1), dark)
        canvas.fillEllipse(cx: x - 1, cy: base - r / 2 - 1, rx: max(1, r - 2), ry: max(1, r / 2), light)
    }

    func tuft(_ canvas: inout PixelCanvas, x: Int, y: Int, _ color: PixelColor) {
        canvas.plot(x, y, color)
        canvas.plot(x - 1, y - 1, color)
        canvas.plot(x + 1, y - 1, color)
        canvas.plot(x, y - 2, color)
    }

    func flower(_ canvas: inout PixelCanvas, x: Int, y: Int, petal: PixelColor, center: PixelColor) {
        canvas.plot(x, y + 1, PixelColor(0x3E7A44))
        canvas.plot(x - 1, y, petal)
        canvas.plot(x + 1, y, petal)
        canvas.plot(x, y - 1, petal)
        canvas.plot(x, y, center)
    }

    func cottage(_ canvas: inout PixelCanvas, x: Int, base: Int, width w: Int, height h: Int, wall: PixelColor,
                 wallShade: PixelColor, roof: PixelColor, roofShade: PixelColor, window: PixelColor,
                 outline: PixelColor) {
        let left = x - w / 2
        let wallTop = base - h
        canvas.fillRect(x: left, y: wallTop, width: w, height: h, wall)
        canvas.vline(x: left + w - 1, y: wallTop, length: h, wallShade)
        // Roof overhangs by one pixel and rises in steps.
        let roofHeight = w / 2 + 1
        for row in 0..<roofHeight {
            let inset = row
            let yy = wallTop - roofHeight + row + 1
            canvas.hline(x: left - 1 + (roofHeight - 1 - inset), y: yy, length: w + 2 - 2 * (roofHeight - 1 - inset), roof)
            canvas.plot(left - 1 + (roofHeight - 1 - inset), yy, outline)
            canvas.plot(left + w + (inset - roofHeight + 1), yy, outline)
        }
        canvas.hline(x: left - 1, y: wallTop, length: w + 2, roofShade)
        // Chimney with a puff of smoke.
        canvas.fillRect(x: left + w - 4, y: wallTop - roofHeight - 1, width: 2, height: 3, PixelColor(0x7A5638))
        canvas.plot(left + w - 4, wallTop - roofHeight - 3, PixelColor(0xE8E2D6, alpha: 180))
        canvas.plot(left + w - 3, wallTop - roofHeight - 5, PixelColor(0xE8E2D6, alpha: 120))
        // Door and glowing windows.
        canvas.fillRect(x: x - 1, y: base - 4, width: 3, height: 4, PixelColor(0x6B4A2F))
        canvas.fillRect(x: left + 2, y: wallTop + 2, width: 2, height: 2, window)
        if w > 9 { canvas.fillRect(x: left + w - 4, y: wallTop + 2, width: 2, height: 2, window) }
    }

    func crystal(_ canvas: inout PixelCanvas, x: Int, base: Int, height h: Int, light: PixelColor, mid: PixelColor,
                 dark: PixelColor, glow: Bool) {
        let w = max(2, h / 3)
        if glow { canvas.fillEllipse(cx: x, cy: base - h / 2, rx: w + 3, ry: h / 2 + 2, light.withAlpha(45)) }
        for row in 0..<h {
            let half = row < w ? row : w
            let yy = base - h + row
            canvas.hline(x: x - half, y: yy, length: half, light)
            canvas.hline(x: x, y: yy, length: half + 1, mid)
            canvas.plot(x + half, yy, dark)
        }
    }

    func water(_ canvas: inout PixelCanvas, top: Int, bottom: Int, base: PixelColor, deep: PixelColor,
               shine: PixelColor, seed: Int) {
        for row in top..<bottom {
            let t = Double(row - top) / Double(max(1, bottom - top))
            canvas.hline(x: 0, y: row, length: width, t > 0.5 ? deep : base)
        }
        var local = SplitMix64(seed: UInt64(seed))
        for row in stride(from: top + 1, to: bottom, by: 2) {
            for _ in 0..<(width / 24 + 1) {
                let x = local.int(0...(width - 1))
                canvas.hline(x: x, y: row, length: local.int(2...5), shine)
            }
        }
    }

    /// The walking path plus the grass band above and below it.
    mutating func path(_ canvas: inout PixelCanvas, footY: Int, grass: PixelColor, grassDark: PixelColor,
                       path: PixelColor, pathDark: PixelColor, pathLight: PixelColor) {
        let top = footY - 4
        canvas.fillRect(x: 0, y: top, width: width, height: height - top, grass)
        canvas.fillRect(x: 0, y: footY - 2, width: width, height: 5, path)
        canvas.hline(x: 0, y: footY - 2, length: width, pathLight)
        canvas.hline(x: 0, y: footY + 3, length: width, pathDark)
        for x in stride(from: 0, to: width, by: 1) where rng.chance(0.12) {
            canvas.plot(x, footY + rng.int(-1...2), rng.chance(0.5) ? pathDark : pathLight)
        }
        canvas.hline(x: 0, y: top, length: width, grassDark)
        for x in stride(from: 0, to: width, by: 3) where rng.chance(0.5) {
            canvas.plot(x, top - 1, grass)
        }
    }

    mutating func foregroundGrass(_ canvas: inout PixelCanvas, from top: Int, count: Int, color: PixelColor) {
        for _ in 0..<count {
            tuft(&canvas, x: rng.int(0...(width - 1)), y: rng.int(top, height - 1), color)
        }
    }
}
