import Foundation
import WalkscapeDomain

/// Colour script for a biome. Kept separate from the painting code so the
/// mood of a zone can be tuned without touching shapes.
struct BiomeStyle {
    var sky: [PixelColor]
    var sun: PixelColor?
    var clouds = true
    var cloud = PixelColor(0xFFFBF0)
    var cloudShade = PixelColor(0xDCE8EE)
    var stars = false

    static func style(for biome: Biome) -> BiomeStyle {
        switch biome {
        case .meadow, .riverside, .rollingHills:
            return BiomeStyle(sky: [PixelColor(0x6FA8D6), PixelColor(0x8DBEE0), PixelColor(0xB4D6E8), PixelColor(0xDDEDE8)],
                              sun: PixelColor(0xFFF1B8))
        case .pineForest:
            return BiomeStyle(sky: [PixelColor(0x7FAFC4), PixelColor(0x9CC2CC), PixelColor(0xBFD6CF), PixelColor(0xDCE6D2)],
                              sun: PixelColor(0xFFF1B8))
        case .lakeside:
            return BiomeStyle(sky: [PixelColor(0x7EA9D8), PixelColor(0x9DBFE2), PixelColor(0xC3D8EA), PixelColor(0xE6EEEA)],
                              sun: PixelColor(0xFFF4C8))
        case .village:
            return BiomeStyle(sky: [PixelColor(0x7FA3CF), PixelColor(0xA9B9D2), PixelColor(0xE6C9A8), PixelColor(0xF5D9A8)],
                              sun: PixelColor(0xFFE29A), cloud: PixelColor(0xFFF1DE), cloudShade: PixelColor(0xF0C9A8))
        case .crystalCaves:
            return BiomeStyle(sky: [PixelColor(0x15122A), PixelColor(0x1E1A38), PixelColor(0x2A2348), PixelColor(0x352C58)],
                              sun: nil, clouds: false)
        case .snowyRidge:
            return BiomeStyle(sky: [PixelColor(0x8FB0D0), PixelColor(0xA9C3DC), PixelColor(0xC8D9E8), PixelColor(0xE8F0F6)],
                              sun: PixelColor(0xFFFBEA), cloudShade: PixelColor(0xD6E2EE))
        case .cloudForest:
            return BiomeStyle(sky: [PixelColor(0x86B3AE), PixelColor(0x9EC4BC), PixelColor(0xBAD6CB), PixelColor(0xD6E8DC)],
                              sun: nil, cloud: PixelColor(0xEEF6F0), cloudShade: PixelColor(0xCFE2D8))
        case .summit:
            return BiomeStyle(sky: [PixelColor(0x3F4A86), PixelColor(0x7A5E9A), PixelColor(0xD88A9A), PixelColor(0xF4B98A)],
                              sun: PixelColor(0xFFE0A0), cloud: PixelColor(0xFFE6D0), cloudShade: PixelColor(0xE8A8A8),
                              stars: true)
        }
    }
}

private let outline = PixelColor(0x1E2233)

extension ScenePainter {
    // MARK: Meadow

    mutating func paintMeadow(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                              _ style: BiomeStyle, _ footY: Int) {
        _ = ridge(&far, base: y(0.58), spec: [(1, 4), (3, 2)], fill: PixelColor(0xA9CCB0), rim: PixelColor(0xC2DCC0))
        let tops = ridge(&mid, base: y(0.66), spec: [(2, 3), (5, 1.2)], fill: PixelColor(0x7DB566), rim: PixelColor(0x9BCB78))
        for x in positions(count: max(3, width / 30), jitter: 6) {
            let wx = ((x % width) + width) % width
            if rng.chance(0.6) {
                roundTree(&mid, x: x, base: tops[wx] + 2, radius: rng.int(3...4), dark: PixelColor(0x4F8A5B),
                          light: PixelColor(0x6FA86A), trunk: PixelColor(0x6B4A2F))
            } else {
                bush(&mid, x: x, base: tops[wx] + 2, radius: 3, dark: PixelColor(0x5E9E4A), light: PixelColor(0x7FBA5E))
            }
        }
        path(&ground, footY: footY, grass: PixelColor(0x7DBA5E), grassDark: PixelColor(0x5E9E4A),
             path: PixelColor(0xD2AE74), pathDark: PixelColor(0xA9824F), pathLight: PixelColor(0xE3C690))
        meadowFlowers(&ground, footY: footY)
    }

    mutating func meadowFlowers(_ ground: inout PixelCanvas, footY: Int) {
        let petals = [PixelColor(0xFFF6E0), PixelColor(0xF2B7A8), PixelColor(0xE3B04B), PixelColor(0xB9A6E0)]
        for _ in 0..<(width / 6) {
            let fy = rng.chance(0.3) ? rng.int(footY - 4, footY - 3) : rng.int(footY + 5, height - 2)
            flower(&ground, x: rng.int(0...(width - 1)), y: fy, petal: petals[rng.int(0...3)], center: PixelColor(0xE3B04B))
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 5, color: PixelColor(0x5E9E4A))
    }

    // MARK: Riverside

    mutating func paintRiverside(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                 _ style: BiomeStyle, _ footY: Int) {
        let farTops = ridge(&far, base: y(0.6), spec: [(2, 2), (5, 1)], fill: PixelColor(0x9CC2A6))
        for x in positions(count: width / 9, jitter: 3) {
            let wx = ((x % width) + width) % width
            roundTree(&far, x: x, base: farTops[wx] + 1, radius: 3, dark: PixelColor(0x86B294), light: PixelColor(0x9CC2A6),
                      trunk: PixelColor(0x86B294))
        }
        let tops = ridge(&mid, base: y(0.68), spec: [(3, 1.5)], fill: PixelColor(0x73AE60), rim: PixelColor(0x93C474))
        for x in positions(count: max(3, width / 26), jitter: 5) {
            let wx = ((x % width) + width) % width
            roundTree(&mid, x: x, base: tops[wx] + 2, radius: rng.int(3...5), dark: PixelColor(0x4F8A5B),
                      light: PixelColor(0x6FA86A), trunk: PixelColor(0x6B4A2F))
        }
        // Grass bank, then a wooden boardwalk, then the river in front.
        ground.fillRect(x: 0, y: footY - 6, width: width, height: 4, PixelColor(0x7DBA5E))
        ground.hline(x: 0, y: footY - 6, length: width, PixelColor(0x5E9E4A))
        let plank = PixelColor(0xB0834F)
        ground.fillRect(x: 0, y: footY - 2, width: width, height: 4, plank)
        ground.hline(x: 0, y: footY - 2, length: width, PixelColor(0xD0A06A))
        ground.hline(x: 0, y: footY + 2, length: width, PixelColor(0x6B4A2F))
        for x in stride(from: 0, to: width, by: 5) { ground.vline(x: x, y: footY - 1, length: 3, PixelColor(0x8A6238)) }
        for x in stride(from: 2, to: width, by: 16) {
            ground.fillRect(x: x, y: footY - 5, width: 1, height: 4, PixelColor(0x6B4A2F))
            ground.fillRect(x: x, y: footY + 3, width: 2, height: 4, PixelColor(0x5A3E26))
        }
        ground.hline(x: 0, y: footY - 5, length: width, PixelColor(0x8A6238))
        water(&ground, top: footY + 3, bottom: height, base: PixelColor(0x5B9BC8), deep: PixelColor(0x4A85B4),
              shine: PixelColor(0xA8D4EE), seed: 7)
        for x in positions(count: width / 14, jitter: 4) {
            for i in 0..<3 { ground.vline(x: x + i * 2, y: footY + 2 - i, length: 4, PixelColor(0x5E9E4A)) }
        }
    }

    // MARK: Pine forest

    mutating func paintPineForest(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                  _ style: BiomeStyle, _ footY: Int) {
        far.fillRect(x: 0, y: y(0.62), width: width, height: height, PixelColor(0x7FA897))
        for x in positions(count: width / 6, jitter: 2) {
            pine(&far, x: x, base: y(0.66), height: rng.int(14...22), dark: PixelColor(0x7FA897), light: PixelColor(0x93B8A6))
        }
        mid.fillRect(x: 0, y: y(0.7), width: width, height: height, PixelColor(0x2F5D46))
        for x in positions(count: width / 8, jitter: 3) {
            pine(&mid, x: x, base: y(0.74), height: rng.int(22...32), dark: PixelColor(0x2F5D46), light: PixelColor(0x417A56),
                 trunk: PixelColor(0x5A3E26))
        }
        // Sun shafts through the trees.
        for x in positions(count: 3, jitter: 10) {
            for row in y(0.2)..<y(0.72) {
                mid.plot(x + (row - y(0.2)) / 3, row, PixelColor(0xFFF1B8, alpha: 40))
                mid.plot(x + 1 + (row - y(0.2)) / 3, row, PixelColor(0xFFF1B8, alpha: 30))
            }
        }
        path(&ground, footY: footY, grass: PixelColor(0x587A3A), grassDark: PixelColor(0x40602A),
             path: PixelColor(0xA8845A), pathDark: PixelColor(0x7A5A3A), pathLight: PixelColor(0xC09A6C))
        for _ in 0..<(width / 14) {
            let mx = rng.int(0...(width - 1))
            let my = rng.int(footY + 6, height - 2)
            ground.plot(mx, my, PixelColor(0xFFF6E0))
            ground.hline(x: mx - 1, y: my - 1, length: 3, PixelColor(0xC0583E))
            ground.plot(mx, my - 2, PixelColor(0xC0583E))
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 5, color: PixelColor(0x40602A))
    }

    // MARK: Rolling hills

    mutating func paintRollingHills(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                    _ style: BiomeStyle, _ footY: Int) {
        _ = ridge(&far, base: y(0.5), spec: [(1, 6), (2, 3)], fill: PixelColor(0xB4D69A), rim: PixelColor(0xC8E2AE))
        _ = ridge(&far, base: y(0.6), spec: [(2, 5), (3, 2)], fill: PixelColor(0x96C47A), rim: PixelColor(0xAED48E))
        let tops = ridge(&mid, base: y(0.7), spec: [(2, 4), (4, 1.5)], fill: PixelColor(0x74AE58), rim: PixelColor(0x8EC46C))
        // Dry-stone wall following the hill line.
        for x in 0..<width where x % 3 != 2 {
            mid.plot(x, tops[x] + 3, PixelColor(0xB8B0A0))
            mid.plot(x, tops[x] + 4, PixelColor(0x8F887A))
        }
        // Sheep.
        for x in positions(count: max(2, width / 40), jitter: 8) {
            let wx = ((x % width) + width) % width
            let sy = tops[wx] + 2
            mid.fillEllipse(cx: x, cy: sy - 2, rx: 3, ry: 2, PixelColor(0xFFFBF0))
            mid.plot(x - 2, sy - 3, PixelColor(0xE6E0D2))
            mid.fillRect(x: x + 3, y: sy - 3, width: 2, height: 2, PixelColor(0x2E2A2A))
            mid.plot(x - 2, sy, PixelColor(0x2E2A2A))
            mid.plot(x + 2, sy, PixelColor(0x2E2A2A))
        }
        path(&ground, footY: footY, grass: PixelColor(0x7DBA5E), grassDark: PixelColor(0x5E9E4A),
             path: PixelColor(0xD2AE74), pathDark: PixelColor(0xA9824F), pathLight: PixelColor(0xE3C690))
        // Fence posts along the path.
        for x in stride(from: 3, to: width, by: 12) {
            ground.vline(x: x, y: footY - 9, length: 6, PixelColor(0x8A6238))
            ground.plot(x, footY - 9, PixelColor(0xB0834F))
        }
        for x in 0..<width {
            ground.plot(x, footY - 7, PixelColor(0xB0834F))
        }
        meadowFlowers(&ground, footY: footY)
    }

    // MARK: Lakeside

    mutating func paintLakeside(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                _ style: BiomeStyle, _ footY: Int) {
        let horizon = y(0.6)
        let peakTerms = terms([(2, 9), (5, 3), (9, 1.2)])
        for x in 0..<width {
            let top = horizon - 10 + Int(wave(x, peakTerms).rounded())
            far.vline(x: x, y: top, length: horizon - top, PixelColor(0x8A9FC0))
            far.plot(x, top, PixelColor(0xF4F7FA))
            if top < horizon - 13 { far.vline(x: x, y: top, length: 3, PixelColor(0xE6EDF4)) }
            // Mirror reflection in the lake, broken up by ripples.
            for row in 0..<max(0, horizon - top) where (row + x) % 3 != 0 {
                far.plot(x, horizon + row + 1, PixelColor(0x8AA6C8, alpha: 150))
            }
        }
        water(&mid, top: horizon + 1, bottom: y(0.76), base: PixelColor(0x7FB2D8, alpha: 200), deep: PixelColor(0x6A9FCC, alpha: 210),
              shine: PixelColor(0xD6ECF8), seed: 11)
        mid.hline(x: 0, y: horizon + 1, length: width, PixelColor(0xB8D8EE))
        for x in positions(count: width / 10, jitter: 3) {
            mid.vline(x: x, y: y(0.72), length: 5, PixelColor(0x5E9E4A))
            mid.vline(x: x + 1, y: y(0.7), length: 7, PixelColor(0x6FAA55))
            mid.plot(x + 1, y(0.7), PixelColor(0x8A6238))
        }
        path(&ground, footY: footY, grass: PixelColor(0x86BE64), grassDark: PixelColor(0x669E4C),
             path: PixelColor(0xE2C894), pathDark: PixelColor(0xBFA06A), pathLight: PixelColor(0xF0DCB0))
        meadowFlowers(&ground, footY: footY)
    }

    // MARK: Village

    mutating func paintVillage(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                               _ style: BiomeStyle, _ footY: Int) {
        let tops = ridge(&far, base: y(0.6), spec: [(2, 3), (3, 1.5)], fill: PixelColor(0xA6BE8E), rim: PixelColor(0xBCD0A0))
        for x in positions(count: width / 16, jitter: 4) {
            let wx = ((x % width) + width) % width
            roundTree(&far, x: x, base: tops[wx] + 1, radius: 3, dark: PixelColor(0x8EAE7A), light: PixelColor(0xA6BE8E),
                      trunk: PixelColor(0x8EAE7A))
        }
        let base = y(0.75)
        mid.fillRect(x: 0, y: base - 1, width: width, height: height, PixelColor(0x7DB566))
        let roofs = [(PixelColor(0xB5553C), PixelColor(0x8E3F2C)), (PixelColor(0x7A5638), PixelColor(0x5A3E26)),
                     (PixelColor(0x5D7FA8), PixelColor(0x46628A))]
        for (i, x) in positions(count: max(2, width / 34), jitter: 4).enumerated() {
            let roof = roofs[i % roofs.count]
            cottage(&mid, x: x, base: base, width: rng.int(13...17), height: rng.int(9...12),
                    wall: PixelColor(0xF4EBD0), wallShade: PixelColor(0xD9CCAA), roof: roof.0, roofShade: roof.1,
                    window: PixelColor(0xFFD66B), outline: roof.1)
            bush(&mid, x: x + 10, base: base, radius: 2, dark: PixelColor(0x5E9E4A), light: PixelColor(0x7FBA5E))
        }
        path(&ground, footY: footY, grass: PixelColor(0x7DBA5E), grassDark: PixelColor(0x5E9E4A),
             path: PixelColor(0xB4AC9C), pathDark: PixelColor(0x8A8274), pathLight: PixelColor(0xCEC8BA))
        // Cobbles.
        for x in stride(from: 0, to: width, by: 3) {
            ground.plot(x + (x / 3) % 2, footY, PixelColor(0x8A8274))
            ground.plot(x + 1, footY + 2, PixelColor(0x9A9284))
        }
        // Lamp posts.
        for x in stride(from: 9, to: width, by: 40) {
            ground.vline(x: x, y: footY - 12, length: 9, PixelColor(0x2E3A4A))
            ground.fillRect(x: x - 1, y: footY - 14, width: 3, height: 2, PixelColor(0xFFD66B))
            ground.fillEllipse(cx: x, cy: footY - 13, rx: 3, ry: 3, PixelColor(0xFFD66B, alpha: 50))
        }
        meadowFlowers(&ground, footY: footY)
    }

    // MARK: Crystal caves

    mutating func paintCaves(_ sky: inout PixelCanvas, _ far: inout PixelCanvas, _ mid: inout PixelCanvas,
                             _ ground: inout PixelCanvas, _ style: BiomeStyle, _ footY: Int) {
        // Cave ceiling with stalactites (part of the far layer so it scrolls).
        let ceiling = terms([(3, 3), (7, 1.5)])
        for x in 0..<width {
            let bottom = y(0.12) + Int(wave(x, ceiling).rounded())
            far.vline(x: x, y: 0, length: bottom, PixelColor(0x2A2442))
            far.plot(x, bottom, PixelColor(0x3A3260))
        }
        for x in positions(count: width / 9, jitter: 3) {
            let length = rng.int(4...10)
            for row in 0..<length {
                let half = max(0, (length - row) / 3)
                far.hline(x: x - half, y: y(0.12) + row, length: half * 2 + 1, PixelColor(0x2A2442))
            }
        }
        // Distant rock pillars.
        for x in positions(count: width / 22, jitter: 5) {
            far.fillRect(x: x, y: y(0.15), width: rng.int(5...8), height: y(0.7), PixelColor(0x2E2850))
        }
        _ = ridge(&far, base: y(0.66), spec: [(3, 3), (5, 2)], fill: PixelColor(0x302A54), rim: PixelColor(0x40386A))
        // Glowing crystals.
        let palettes = [(PixelColor(0xB8F4F8), PixelColor(0x7FE0E8), PixelColor(0x3FA8C0)),
                        (PixelColor(0xF8C8F0), PixelColor(0xE58AD8), PixelColor(0xA855A0)),
                        (PixelColor(0xD8CCFF), PixelColor(0xA898F0), PixelColor(0x6A5AC0))]
        mid.fillRect(x: 0, y: y(0.74), width: width, height: height, PixelColor(0x3A3360))
        for (i, x) in positions(count: max(3, width / 18), jitter: 5).enumerated() {
            let p = palettes[i % palettes.count]
            crystal(&mid, x: x, base: y(0.75), height: rng.int(7...14), light: p.0, mid: p.1, dark: p.2, glow: true)
            crystal(&mid, x: x + 4, base: y(0.75), height: rng.int(4...7), light: p.0, mid: p.1, dark: p.2, glow: false)
        }
        path(&ground, footY: footY, grass: PixelColor(0x4A4470), grassDark: PixelColor(0x3A3460),
             path: PixelColor(0x6E6890), pathDark: PixelColor(0x504A74), pathLight: PixelColor(0x8A84AA))
        for x in positions(count: width / 12, jitter: 4) {
            crystal(&ground, x: x, base: height - 2, height: rng.int(3...6), light: palettes[0].0, mid: palettes[0].1,
                    dark: palettes[0].2, glow: true)
        }
        // Fireflies / sparkles in the dark.
        for _ in 0..<(width / 10) {
            sky.plot(rng.int(0...(width - 1)), rng.int(y(0.2), y(0.6)), PixelColor(0xB8F4F8, alpha: UInt8(rng.int(90...200))))
        }
    }

    // MARK: Snowy ridge

    mutating func paintSnowyRidge(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                  _ style: BiomeStyle, _ footY: Int) {
        let peaks = terms([(2, 10), (3, 4), (7, 1.5)])
        let horizon = y(0.66)
        for x in 0..<width {
            let top = y(0.42) + Int(wave(x, peaks).rounded())
            far.vline(x: x, y: top, length: horizon - top + 4, PixelColor(0xA9BDD4))
            far.vline(x: x, y: top, length: max(2, (horizon - top) / 3), PixelColor(0xF4F7FA))
            if x % 2 == 0 { far.plot(x, top + max(2, (horizon - top) / 3), PixelColor(0xD6E2EE)) }
        }
        mid.fillRect(x: 0, y: y(0.72), width: width, height: height, PixelColor(0xE8F0F6))
        for x in positions(count: width / 11, jitter: 3) {
            pine(&mid, x: x, base: y(0.74), height: rng.int(14...22), dark: PixelColor(0x2F5D52), light: PixelColor(0x3F7364),
                 trunk: PixelColor(0x5A3E26), snow: PixelColor(0xF4F7FA))
        }
        path(&ground, footY: footY, grass: PixelColor(0xF2F6FA), grassDark: PixelColor(0xD0DCE8),
             path: PixelColor(0xC6D2DF), pathDark: PixelColor(0xA9B8C8), pathLight: PixelColor(0xDCE5EE))
        for _ in 0..<(width / 6) {
            ground.plot(rng.int(0...(width - 1)), rng.int(footY + 5, height - 1), PixelColor(0xD0DCE8))
        }
    }

    // MARK: Cloud forest

    mutating func paintCloudForest(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                   _ style: BiomeStyle, _ footY: Int) {
        for x in positions(count: width / 14, jitter: 4) {
            far.fillRect(x: x, y: y(0.1), width: 3, height: y(0.6), PixelColor(0x8DB2A6))
            far.fillEllipse(cx: x + 1, cy: y(0.18), rx: 8, ry: 5, PixelColor(0x8DB2A6))
        }
        far.fillRect(x: 0, y: y(0.62), width: width, height: height, PixelColor(0x8DB2A6))
        for x in positions(count: max(2, width / 30), jitter: 6) {
            let w = rng.int(4...6)
            mid.fillRect(x: x, y: 0, width: w, height: y(0.75), PixelColor(0x4E6B4A))
            mid.vline(x: x, y: 0, length: y(0.75), PixelColor(0x3E5A3C))
            // Moss patches and hanging vines.
            for row in stride(from: rng.int(2...6), to: y(0.72), by: rng.int(5...8)) {
                mid.fillRect(x: x + 1, y: row, width: w - 1, height: 2, PixelColor(0x6FA86A))
            }
            mid.fillEllipse(cx: x + w / 2, cy: 2, rx: 12, ry: 6, PixelColor(0x3E6E52))
            mid.fillEllipse(cx: x + w / 2 - 2, cy: 1, rx: 9, ry: 4, PixelColor(0x4F8A5B))
            for vine in stride(from: x - 8, to: x + 14, by: 4) {
                mid.vline(x: vine, y: 6, length: rng.int(4...12), PixelColor(0x5E9E4A))
            }
        }
        // Drifting mist band.
        for x in 0..<width {
            let thickness = 3 + Int((2 * sin(2 * .pi * Double(x) * 2 / Double(width))).rounded())
            mid.vline(x: x, y: y(0.58), length: thickness, PixelColor(0xEEF6F0, alpha: 110))
        }
        path(&ground, footY: footY, grass: PixelColor(0x4F8A5B), grassDark: PixelColor(0x3E7050),
             path: PixelColor(0x8A7454), pathDark: PixelColor(0x6A563E), pathLight: PixelColor(0xA08A68))
        // Ferns and glowcaps.
        for x in positions(count: width / 10, jitter: 3) {
            for i in -2...2 { ground.plot(x + i, footY - 5 - (2 - abs(i)), PixelColor(0x6FA86A)) }
            ground.vline(x: x, y: footY - 6, length: 3, PixelColor(0x5E9E4A))
        }
        for _ in 0..<(width / 16) {
            let mx = rng.int(0...(width - 1))
            let my = rng.int(footY + 6, height - 2)
            ground.fillEllipse(cx: mx, cy: my - 1, rx: 3, ry: 3, PixelColor(0x7FE0E8, alpha: 50))
            ground.hline(x: mx - 1, y: my - 1, length: 3, PixelColor(0x7FE0E8))
            ground.plot(mx, my, PixelColor(0xFFF6E0))
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 5, color: PixelColor(0x3E7050))
    }

    // MARK: Summit

    mutating func paintSummit(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                              _ style: BiomeStyle, _ footY: Int) {
        // Distant peaks poking out of a sea of clouds.
        let peaks = terms([(3, 6), (5, 2)])
        for x in 0..<width {
            let top = y(0.5) + Int(wave(x, peaks).rounded())
            far.vline(x: x, y: top, length: y(0.62) - top, PixelColor(0x8E7FA8))
            far.plot(x, top, PixelColor(0xF4D8E0))
        }
        let sea = terms([(4, 1.5), (9, 1)])
        for x in 0..<width {
            let top = y(0.6) + Int(wave(x, sea).rounded())
            mid.vline(x: x, y: top, length: height - top, PixelColor(0xF7DCCB))
            mid.plot(x, top, PixelColor(0xFFF1E6))
            mid.vline(x: x, y: top + 4, length: 2, PixelColor(0xEBC2B6))
        }
        // Rocky summit path.
        let rock = terms([(2, 1.5), (5, 1)])
        for x in 0..<width {
            let top = footY - 5 + Int(wave(x, rock).rounded())
            ground.vline(x: x, y: top, length: height - top, PixelColor(0x8A8072))
            ground.plot(x, top, PixelColor(0xB0A694))
        }
        ground.fillRect(x: 0, y: footY - 2, width: width, height: 5, PixelColor(0xA89E8A))
        ground.hline(x: 0, y: footY - 2, length: width, PixelColor(0xC2B8A4))
        ground.hline(x: 0, y: footY + 3, length: width, PixelColor(0x6E6658))
        for _ in 0..<(width / 5) {
            ground.plot(rng.int(0...(width - 1)), rng.int(footY + 5, height - 1), PixelColor(0x6E6658))
        }
        // Cairns with prayer-flag style bunting.
        for x in stride(from: 12, to: width, by: 44) {
            ground.fillRect(x: x - 2, y: footY - 6, width: 5, height: 2, PixelColor(0x9A9080))
            ground.fillRect(x: x - 1, y: footY - 8, width: 3, height: 2, PixelColor(0xB0A694))
            ground.vline(x: x, y: footY - 16, length: 8, PixelColor(0x5A3E26))
            ground.fillRect(x: x + 1, y: footY - 16, width: 5, height: 3, PixelColor(0xC0583E))
            ground.plot(x + 1, y: footY - 16, outline)
        }
    }
}

private extension PixelCanvas {
    mutating func plot(_ x: Int, y: Int, _ color: PixelColor) { plot(x, y, color) }
}
