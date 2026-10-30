import Foundation
import WalkscapeDomain

/// Seasonal look for any biome, layered over the normal procedural scene:
/// one recolour pass plus a few decorations, so every zone gets all four
/// seasons without separate artwork. Zone progression is never affected.
public enum SeasonalPass {
    /// Underground zones look the same all year.
    static let unaffected: Set<Biome> = [.crystalCaves]

    public static func apply(_ layers: SceneLayers, season: Season) -> SceneLayers {
        guard !unaffected.contains(layers.biome) else { return layers }
        var sky = layers.sky
        var far = layers.far
        var mid = layers.mid
        var ground = layers.ground
        let seed = UInt64(truncatingIfNeeded: layers.biome.rawValue.stableHash)

        sky.recolor { color, _, _ in tintSky(color, season) }
        far.recolor { color, x, y in recolor(color, x: x, y: y, season: season, seed: seed, layer: 0) }
        mid.recolor { color, x, y in recolor(color, x: x, y: y, season: season, seed: seed, layer: 1) }
        ground.recolor { color, x, y in recolor(color, x: x, y: y, season: season, seed: seed, layer: 2) }

        return SceneLayers(biome: layers.biome, width: layers.width, height: layers.height, sky: sky, clouds: layers.clouds,
                           far: far, mid: mid, ground: ground, footY: layers.footY)
    }

    static func isFoliage(_ c: PixelColor) -> Bool { Int(c.g) > Int(c.r) + 12 && c.g >= c.b }
    static func isWater(_ c: PixelColor) -> Bool { Int(c.b) > Int(c.r) + 20 && c.b > c.g }

    static func tintSky(_ color: PixelColor, _ season: Season) -> PixelColor {
        guard color.a > 0 else { return color }
        switch season {
        case .winter: return color.mixed(with: PixelColor(0xC9D6E2, alpha: color.a), 0.25)
        case .summer: return color.mixed(with: PixelColor(0xFFE2A8, alpha: color.a), 0.08)
        case .autumn: return color.mixed(with: PixelColor(0xF2C79A, alpha: color.a), 0.10)
        case .spring: return color
        }
    }

    static func recolor(_ c: PixelColor, x: Int, y: Int, season: Season, seed: UInt64, layer: Int) -> PixelColor {
        guard c.a > 0 else { return c }
        let noise = hash(x, y, seed &+ UInt64(layer))
        switch season {
        case .winter:
            if isFoliage(c) { return c.mixed(with: PixelColor(0xEEF4F8, alpha: c.a), 0.55) }
            if isWater(c) && layer == 2 { return c.mixed(with: PixelColor(0xCFE6F0, alpha: c.a), 0.5) }
            return c.mixed(with: PixelColor(0xDCE6EE, alpha: c.a), 0.12)
        case .autumn:
            guard isFoliage(c) else { return c }
            let palette: [UInt32] = [0xD9822B, 0xB5452A, 0xE0B040, 0xC9662E]
            let target = PixelColor(palette[Int(noise % UInt64(palette.count))], alpha: c.a)
            // Keep the original shading: darker greens become darker oranges.
            let light = Double(Int(c.r) + Int(c.g) + Int(c.b)) / 3 / 150
            let shaded = PixelColor(r: scale(target.r, light), g: scale(target.g, light), b: scale(target.b, light), a: c.a)
            return c.mixed(with: shaded, 0.7)
        case .spring:
            guard isFoliage(c) else { return c }
            if layer < 2 && noise % 100 < 5 {
                return PixelColor(noise % 3 == 0 ? 0xFFF3F6 : 0xF4B6C8, alpha: c.a)
            }
            return c.mixed(with: PixelColor(0x8FD16A, alpha: c.a), 0.22)
        case .summer:
            guard isFoliage(c) else { return c }
            return c.mixed(with: PixelColor(0x5DB04A, alpha: c.a), 0.18)
        }
    }

    static func scale(_ value: UInt8, _ factor: Double) -> UInt8 {
        UInt8(min(255, max(0, (Double(value) * min(1.3, max(0.35, factor))).rounded())))
    }

    static func hash(_ x: Int, _ y: Int, _ seed: UInt64) -> UInt64 {
        var h = seed ^ (UInt64(truncatingIfNeeded: x) &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(truncatingIfNeeded: y) &* 0xC2B2_AE3D_27D4_EB4F)
        h ^= h >> 31
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 29
        return h
    }
}

/// Colour mood for team worlds: shifts any biome toward the world's palette
/// so every world has its own look without separate artwork.
public enum WorldTintPass {
    public static func apply(_ layers: SceneLayers, tint: WorldTint) -> SceneLayers {
        let (skyTone, landTone, amount): (UInt32, UInt32, Double) = {
            switch tint {
            case .enchanted: return (0x3A2A5E, 0x6B4FA8, 0.32)
            case .crystal: return (0x9FD8F0, 0x8FB8E8, 0.35)
            case .desert: return (0xF2C27A, 0xD9A05B, 0.35)
            case .skyward: return (0xBFE3FF, 0xF4E6FF, 0.28)
            case .ancient: return (0xC9B48A, 0x9A8466, 0.30)
            }
        }()
        var sky = layers.sky
        var far = layers.far
        var mid = layers.mid
        var ground = layers.ground
        sky.recolor { c, _, _ in c.a == 0 ? c : c.mixed(with: PixelColor(skyTone, alpha: c.a), amount) }
        for index in 0..<3 {
            let weight = amount * [1.0, 0.8, 0.6][index]
            let transform: (PixelColor, Int, Int) -> PixelColor = { c, x, y in
                guard c.a > 0 else { return c }
                // A few magical sparkles in the enchanted and crystal worlds.
                if (tint == .enchanted || tint == .crystal) && index < 2
                    && SeasonalPass.hash(x, y, 0xA11CE + UInt64(index)) % 160 == 0 {
                    return PixelColor(tint == .enchanted ? 0xE8C8FF : 0xE8FCFF, alpha: c.a)
                }
                return c.mixed(with: PixelColor(landTone, alpha: c.a), weight)
            }
            switch index {
            case 0: far.recolor(transform)
            case 1: mid.recolor(transform)
            default: ground.recolor(transform)
            }
        }
        return SceneLayers(biome: layers.biome, width: layers.width, height: layers.height, sky: sky, clouds: layers.clouds,
                           far: far, mid: mid, ground: ground, footY: layers.footY)
    }
}

extension String {
    /// FNV-1a, stable across launches.
    var stableHash: UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return hash
    }
}
