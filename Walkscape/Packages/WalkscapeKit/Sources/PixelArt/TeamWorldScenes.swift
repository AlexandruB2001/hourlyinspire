import Foundation
import WalkscapeDomain

/// The five team-world biomes. Same primitives and tiling rules as the solo
/// trail: decorations use `positions` and wrapping canvases so every layer tiles.
extension ScenePainter {
    // MARK: Enchanted forest

    mutating func paintEnchantedForest(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                       _ style: BiomeStyle, _ footY: Int) {
        let farTops = ridge(&far, base: y(0.6), spec: [(2, 2), (5, 1)], fill: PixelColor(0x3A2E62))
        for x in positions(count: max(3, width / 10), jitter: 3) {
            let wx = ((x % width) + width) % width
            roundTree(&far, x: x, base: farTops[wx] + 2, radius: rng.int(3...5), dark: PixelColor(0x33285A),
                      light: PixelColor(0x46397C), trunk: PixelColor(0x2C2248))
        }
        let tops = ridge(&mid, base: y(0.71), spec: [(3, 1.5)], fill: PixelColor(0x2E5A5A), rim: PixelColor(0x3E7A70))
        for x in positions(count: max(2, width / 34), jitter: 6) {
            let wx = ((x % width) + width) % width
            ancientTree(&mid, x: x, base: tops[wx] + 2, radius: rng.int(4...6))
        }
        // Fireflies drifting between the trees.
        for _ in 0..<(width / 8) {
            let fx = rng.int(0...(width - 1))
            let fy = rng.int(y(0.35), footY - 6)
            mid.plot(fx, fy, PixelColor(0xFFF2A0, alpha: 230))
            mid.plot(fx - 1, fy, PixelColor(0xFFF2A0, alpha: 70))
            mid.plot(fx + 1, fy, PixelColor(0xFFF2A0, alpha: 70))
        }
        path(&ground, footY: footY, grass: PixelColor(0x3E7A62), grassDark: PixelColor(0x2E5E4E),
             path: PixelColor(0x8E7AB0), pathDark: PixelColor(0x6E5C92), pathLight: PixelColor(0xAE9ACC))
        let caps: [UInt32] = [0xF28AC0, 0x8AE0F2, 0xC8F28A, 0xF2C88A]
        for _ in 0..<max(1, width / 12) {
            let my = rng.chance(0.4) ? footY - 4 : rng.int(footY + 7, height - 1)
            glowcap(&ground, x: rng.int(0...(width - 1)), base: my, cap: PixelColor(caps[rng.int(0...3)]))
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 6, color: PixelColor(0x2E5E4E))
    }

    /// A wide old tree with a hanging lantern.
    func ancientTree(_ canvas: inout PixelCanvas, x: Int, base: Int, radius r: Int) {
        let bark = PixelColor(0x4A3A5E)
        canvas.fillRect(x: x - 2, y: base - r * 2, width: 4, height: r * 2 + 1, bark)
        canvas.vline(x: x - 2, y: base - r * 2, length: r * 2, PixelColor(0x6A5480))
        canvas.hline(x: x - 4, y: base, length: 9, bark)
        canvas.plot(x - 3, base - 1, bark)
        canvas.plot(x + 3, base - 1, bark)
        let cy = base - r * 3
        canvas.fillEllipse(cx: x, cy: cy, rx: r + 2, ry: r, PixelColor(0x2E6A66))
        canvas.fillEllipse(cx: x - 2, cy: cy - 1, rx: r, ry: max(1, r - 2), PixelColor(0x3E8A78))
        canvas.fillEllipse(cx: x + 2, cy: cy - 2, rx: max(1, r - 3), ry: max(1, r - 3), PixelColor(0x58A88A))
        let lx = x + r
        canvas.vline(x: lx, y: cy + r - 1, length: 3, PixelColor(0x2C2248))
        canvas.fillEllipse(cx: lx, cy: cy + r + 3, rx: 3, ry: 3, PixelColor(0xFFD27A, alpha: 50))
        canvas.fillRect(x: lx - 1, y: cy + r + 2, width: 2, height: 2, PixelColor(0xFFD27A))
    }

    /// A small glowing mushroom.
    func glowcap(_ canvas: inout PixelCanvas, x: Int, base: Int, cap: PixelColor) {
        canvas.fillEllipse(cx: x, cy: base - 2, rx: 3, ry: 2, cap.withAlpha(60))
        canvas.vline(x: x, y: base - 1, length: 2, PixelColor(0xF4EBD0))
        canvas.hline(x: x - 1, y: base - 2, length: 3, cap)
        canvas.plot(x, base - 3, cap)
    }

    // MARK: Crystal palace

    mutating func paintCrystalPalace(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                     _ style: BiomeStyle, _ footY: Int) {
        let farBase = y(0.62)
        _ = ridge(&far, base: farBase, spec: [(1, 2), (4, 1)], fill: PixelColor(0xB8D0EC), rim: PixelColor(0xDCEAF8))
        // The palace: a cluster of spires, tallest in the middle.
        let palaceX = Int(Double(width) * 0.35)
        for (offset, size) in [(-12, 14), (-6, 22), (0, 30), (6, 22), (12, 14)] {
            crystal(&far, x: palaceX + offset, base: farBase + 1, height: max(4, size * height / 100),
                    light: PixelColor(0xF4F8FF), mid: PixelColor(0xB4C8F0), dark: PixelColor(0x8498D0), glow: offset == 0)
        }
        for x in positions(count: max(2, width / 40), jitter: 6) where abs(x - palaceX) > 20 {
            crystal(&far, x: x, base: farBase + 1, height: max(3, height / 12), light: PixelColor(0xE8F0FC),
                    mid: PixelColor(0xC0D0F0), dark: PixelColor(0x98A8D8), glow: false)
        }
        let tops = ridge(&mid, base: y(0.71), spec: [(2, 2), (5, 1)], fill: PixelColor(0x8EB4D8), rim: PixelColor(0xE6F2FA))
        let tints: [(UInt32, UInt32, UInt32)] = [(0xF6E8FF, 0xC8A8F0, 0x9478C8), (0xE8FCFF, 0x98D8F0, 0x5EA8D0),
                                                 (0xFFF0F6, 0xF0B0D0, 0xC07AA8)]
        for x in positions(count: max(3, width / 18), jitter: 4) {
            let wx = ((x % width) + width) % width
            let tint = tints[rng.int(0...2)]
            crystal(&mid, x: x, base: tops[wx] + 2, height: rng.int(6...11), light: PixelColor(tint.0),
                    mid: PixelColor(tint.1), dark: PixelColor(tint.2), glow: rng.chance(0.4))
        }
        path(&ground, footY: footY, grass: PixelColor(0xDCECF6), grassDark: PixelColor(0xB4CCE0),
             path: PixelColor(0xA8C4E8), pathDark: PixelColor(0x84A4D0), pathLight: PixelColor(0xD4E6FA))
        // Rainbow glints thrown by the crystals, and little shards in the snow.
        let glints: [UInt32] = [0xF4A8C8, 0xF4E08A, 0x9CE6B0, 0x9CC8F4, 0xC8A8F4]
        for _ in 0..<max(1, width / 10) {
            ground.plot(rng.int(0...(width - 1)), rng.int(footY - 2, footY + 2), PixelColor(glints[rng.int(0...4)]))
        }
        for x in positions(count: max(1, width / 16), jitter: 4) {
            crystal(&ground, x: x, base: rng.int(footY + 8, height - 1), height: rng.int(3...4), light: PixelColor(0xF4F8FF),
                    mid: PixelColor(0xB4D0F0), dark: PixelColor(0x84A4D0), glow: false)
        }
    }

    // MARK: Desert ruins

    mutating func paintDesertRuins(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                   _ style: BiomeStyle, _ footY: Int) {
        let farBase = y(0.6)
        // A half-buried pyramid behind the dunes.
        let pyramidX = Int(Double(width) * 0.62)
        let pyramidHeight = max(4, height / 5)
        for row in 0..<pyramidHeight {
            let yy = farBase - pyramidHeight + row + 2
            far.hline(x: pyramidX - row, y: yy, length: row + 1, PixelColor(0xF0CC94))
            far.hline(x: pyramidX + 1, y: yy, length: row, PixelColor(0xD4A870))
        }
        _ = ridge(&far, base: farBase, spec: [(1, 3), (2, 2)], fill: PixelColor(0xE8C088), rim: PixelColor(0xF6D8A4))
        let tops = ridge(&mid, base: y(0.71), spec: [(2, 2), (3, 1)], fill: PixelColor(0xD8A868), rim: PixelColor(0xEEC488))
        for x in positions(count: max(3, width / 22), jitter: 5) {
            let wx = ((x % width) + width) % width
            if rng.chance(0.35) {
                palm(&mid, x: x, base: tops[wx] + 2, height: rng.int(10...14))
            } else {
                pillar(&mid, x: x, base: tops[wx] + 2, height: rng.int(8...15), broken: rng.chance(0.5))
            }
        }
        path(&ground, footY: footY, grass: PixelColor(0xE2B678), grassDark: PixelColor(0xC89A5E),
             path: PixelColor(0xF0D6A0), pathDark: PixelColor(0xD0B07A), pathLight: PixelColor(0xFAE6BC))
        // Fallen stone blocks and old pots half in the sand.
        for _ in 0..<max(1, width / 14) {
            let bx = rng.int(0...(width - 1))
            let by = rng.int(footY + 6, height - 2)
            ground.fillRect(x: bx, y: by, width: 4, height: 2, PixelColor(0xC8B48E))
            ground.hline(x: bx, y: by, length: 4, PixelColor(0xE6D6B4))
        }
        for x in positions(count: max(1, width / 30), jitter: 5) {
            ground.fillEllipse(cx: x, cy: footY - 6, rx: 2, ry: 2, PixelColor(0xC0704A))
            ground.hline(x: x - 1, y: footY - 9, length: 3, PixelColor(0xA05A3A))
            ground.plot(x - 1, footY - 7, PixelColor(0xE0946A))
        }
    }

    /// A sandstone column, sometimes snapped off.
    func pillar(_ canvas: inout PixelCanvas, x: Int, base: Int, height h: Int, broken: Bool) {
        let stone = PixelColor(0xE6D6B4)
        let shade = PixelColor(0xBFA982)
        let top = base - h
        canvas.fillRect(x: x - 2, y: top + 2, width: 5, height: h - 2, stone)
        canvas.vline(x: x + 2, y: top + 2, length: h - 2, shade)
        canvas.vline(x: x, y: top + 3, length: max(1, h - 5), shade.withAlpha(140))
        canvas.hline(x: x - 3, y: base - 1, length: 7, stone)
        canvas.hline(x: x - 3, y: base, length: 7, PixelColor(0x9A8462))
        if broken {
            canvas.hline(x: x - 2, y: top + 1, length: 3, stone)
            canvas.plot(x - 2, top, stone)
        } else {
            canvas.fillRect(x: x - 2, y: top, width: 5, height: 2, stone)
            canvas.hline(x: x - 3, y: top - 1, length: 7, shade)
            canvas.hline(x: x - 3, y: top - 2, length: 7, stone)
        }
    }

    /// A gently leaning palm tree.
    func palm(_ canvas: inout PixelCanvas, x: Int, base: Int, height h: Int) {
        for i in 0..<h {
            let tx = x + i / 5
            canvas.hline(x: tx, y: base - i, length: 2, i % 3 == 0 ? PixelColor(0x8A6238) : PixelColor(0xA87A48))
        }
        let tx = x + (h - 1) / 5
        let ty = base - h
        let leaf = PixelColor(0x4E8E46)
        let light = PixelColor(0x74B05A)
        for direction in [-1, 1] {
            for i in 1...5 {
                canvas.plot(tx + direction * i, ty + (i * i) / 8, leaf)
                canvas.plot(tx + direction * i, ty + (i * i) / 8 - 1, i < 4 ? light : leaf)
            }
        }
        canvas.fillRect(x: tx, y: ty - 1, width: 2, height: 2, light)
        canvas.plot(tx, ty + 1, PixelColor(0x6B4A2F))
    }

    // MARK: Sky islands

    mutating func paintSkyIslands(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                  _ style: BiomeStyle, _ footY: Int) {
        for x in positions(count: max(2, width / 45), jitter: 8) {
            floatingIsland(&far, x: x, top: rng.int(y(0.3), y(0.48)), width: rng.int(10...16), grass: PixelColor(0xA8D0B4),
                           rock: PixelColor(0xB8B4CC), shade: PixelColor(0xA4A0BC), waterfall: false)
        }
        // A sea of clouds far below.
        _ = ridge(&far, base: y(0.66), spec: [(4, 1.5), (7, 1)], fill: PixelColor(0xF0F6FC), rim: PixelColor(0xFFFFFF))
        for x in positions(count: max(2, width / 50), jitter: 8) {
            floatingIsland(&mid, x: x, top: rng.int(y(0.42), y(0.54)), width: rng.int(14...20), grass: PixelColor(0x7CC26A),
                           rock: PixelColor(0x9C8A78), shade: PixelColor(0x7E6E60), waterfall: rng.chance(0.6))
        }
        path(&ground, footY: footY, grass: PixelColor(0x84C870), grassDark: PixelColor(0x62A858),
             path: PixelColor(0xE6D2A0), pathDark: PixelColor(0xC4AC78), pathLight: PixelColor(0xF4E4BC))
        // Below the path the island's rocky edge drops away into cloud.
        let edge = min(height - 1, footY + 6)
        let edgeTerms = terms([(5, 1.2), (9, 0.8)])
        for x in 0..<width {
            let drop = edge + Int(wave(x, edgeTerms).rounded())
            ground.vline(x: x, y: drop, length: height - drop, (x / 3) % 2 == 0 ? PixelColor(0x9C8A78) : PixelColor(0x8A7868))
            ground.plot(x, drop, PixelColor(0x62A858))
        }
        for x in positions(count: max(2, width / 12), jitter: 3) {
            ground.fillEllipse(cx: x, cy: height, rx: rng.int(4...7), ry: 3, PixelColor(0xF4F8FC))
        }
        let petals = [PixelColor(0xFFF6E0), PixelColor(0xF2B7A8), PixelColor(0xB9A6E0)]
        for _ in 0..<max(1, width / 10) {
            flower(&ground, x: rng.int(0...(width - 1)), y: rng.chance(0.5) ? footY - 4 : footY + 4,
                   petal: petals[rng.int(0...2)], center: PixelColor(0xE3B04B))
        }
    }

    /// A grassy island with a rocky underside tapering to a point.
    func floatingIsland(_ canvas: inout PixelCanvas, x: Int, top: Int, width w: Int, grass: PixelColor, rock: PixelColor,
                        shade: PixelColor, waterfall: Bool) {
        let half = max(2, w / 2)
        let depth = max(3, w / 2)
        for row in 0..<depth {
            let inset = row * half / depth
            canvas.hline(x: x - half + inset, y: top + 2 + row, length: max(1, (half - inset) * 2), row % 3 == 2 ? shade : rock)
        }
        canvas.fillRect(x: x - half, y: top, width: half * 2, height: 2, grass)
        canvas.hline(x: x - half + 1, y: top - 1, length: max(1, half * 2 - 2), grass)
        canvas.fillEllipse(cx: x - half / 2, cy: top - 2, rx: 2, ry: 2, grass.mixed(with: PixelColor(0x2E5E3E), 0.25))
        if waterfall {
            let wx = x + half - 2
            canvas.vline(x: wx, y: top + 1, length: depth + 6, PixelColor(0xDDF2FF, alpha: 210))
            canvas.vline(x: wx + 1, y: top + 2, length: depth + 3, PixelColor(0xDDF2FF, alpha: 110))
        }
    }

    // MARK: Ancient city

    mutating func paintAncientCity(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                   _ style: BiomeStyle, _ footY: Int) {
        let farTops = ridge(&far, base: y(0.6), spec: [(1, 3), (3, 1)], fill: PixelColor(0x9AA6B8), rim: PixelColor(0xB4BECC))
        let castleX = Int(Double(width) * 0.55)
        castle(&far, x: castleX, base: farTops[castleX % width] + 2, scale: max(1, height / 60))
        // The city wall, with towers and banners.
        let wallTop = y(0.63)
        let wallBottom = y(0.76)
        for x in 0..<width {
            let brick = ((x / 4) + (x % 2)) % 2 == 0 ? PixelColor(0xC8B89A) : PixelColor(0xBCAC8E)
            mid.vline(x: x, y: wallTop, length: wallBottom - wallTop, brick)
            if x % 6 < 3 { mid.vline(x: x, y: wallTop - 2, length: 2, PixelColor(0xC8B89A)) }
        }
        mid.hline(x: 0, y: wallTop, length: width, PixelColor(0xDCCCAE))
        for x in stride(from: 0, to: width, by: 4) { mid.hline(x: x, y: wallTop + 4, length: 2, PixelColor(0xA89878)) }
        for x in positions(count: max(1, width / 50), jitter: 6) {
            mid.fillRect(x: x - 4, y: wallTop - 8, width: 9, height: wallBottom - wallTop + 8, PixelColor(0xD0C0A2))
            mid.vline(x: x + 4, y: wallTop - 8, length: wallBottom - wallTop + 8, PixelColor(0xB0A082))
            for cx in stride(from: x - 4, through: x + 4, by: 2) { mid.plot(cx, wallTop - 9, PixelColor(0xD0C0A2)) }
            mid.fillRect(x: x - 1, y: wallTop - 4, width: 2, height: 3, PixelColor(0x4A3A5E))
            mid.fillRect(x: x - 2, y: wallTop + 1, width: 4, height: 6, PixelColor(0xB8484A))
            mid.plot(x - 2, wallTop + 7, PixelColor(0xB8484A))
            mid.plot(x + 1, wallTop + 7, PixelColor(0xB8484A))
            mid.fillRect(x: x - 1, y: wallTop + 3, width: 2, height: 2, PixelColor(0xF2C84A))
        }
        for x in positions(count: max(2, width / 24), jitter: 5) {
            roundTree(&mid, x: x, base: wallBottom + 1, radius: rng.int(3...4), dark: PixelColor(0x3E6A44),
                      light: PixelColor(0x568A56), trunk: PixelColor(0x6B4A2F))
        }
        path(&ground, footY: footY, grass: PixelColor(0x7AAE5E), grassDark: PixelColor(0x5E9248),
             path: PixelColor(0xB8B0A0), pathDark: PixelColor(0x8C8478), pathLight: PixelColor(0xD4CCBC))
        // Cobbles.
        for row in (footY - 1)...(footY + 2) {
            for x in stride(from: (row % 2) * 2, to: width, by: 4) { ground.plot(x, row, PixelColor(0x9C9486)) }
        }
        // Street lamps.
        for x in stride(from: 6, to: width, by: 32) {
            ground.vline(x: x, y: footY - 13, length: 10, PixelColor(0x3A3A4A))
            ground.fillEllipse(cx: x, cy: footY - 14, rx: 3, ry: 3, PixelColor(0xFFE29A, alpha: 60))
            ground.fillRect(x: x - 1, y: footY - 15, width: 3, height: 2, PixelColor(0xFFE29A))
            ground.hline(x: x - 1, y: footY - 16, length: 3, PixelColor(0x3A3A4A))
        }
        meadowFlowers(&ground, footY: footY)
    }

    /// A distant castle: a keep, two side towers and a tall central tower with flags.
    func castle(_ canvas: inout PixelCanvas, x: Int, base: Int, scale s: Int) {
        let stone = PixelColor(0x8894AA)
        let shade = PixelColor(0x76829A)
        let roof = PixelColor(0x6A5A8E)
        canvas.fillRect(x: x - 6 * s, y: base - 12 * s, width: 12 * s, height: 12 * s, stone)
        for cx in stride(from: x - 6 * s, to: x + 6 * s, by: 2 * s) {
            canvas.fillRect(x: cx, y: base - 13 * s, width: s, height: s, stone)
        }
        for (tx, h) in [(x - 8 * s, 15 * s), (x + 8 * s, 15 * s), (x, 20 * s)] {
            canvas.fillRect(x: tx - 2 * s, y: base - h, width: 4 * s, height: h, stone)
            canvas.vline(x: tx + 2 * s - 1, y: base - h, length: h, shade)
            let roofHeight = 4 * s
            for row in 0...roofHeight {
                let half = row * (2 * s + 1) / roofHeight
                canvas.hline(x: tx - half, y: base - h - roofHeight + row, length: half * 2 + 1, roof)
            }
            canvas.vline(x: tx, y: base - h - roofHeight - 3, length: 3, PixelColor(0x3A3A4A))
            canvas.hline(x: tx + 1, y: base - h - roofHeight - 3, length: 2, PixelColor(0xD85A4A))
            canvas.fillRect(x: tx - s / 2, y: base - h + 3 * s, width: max(1, s), height: 2 * s, PixelColor(0xFFE29A))
        }
        canvas.fillRect(x: x - s, y: base - 4 * s, width: 2 * s + 1, height: 4 * s, PixelColor(0x4A3A5E))
        canvas.fillRect(x: x - 4 * s, y: base - 9 * s, width: s, height: 2 * s, PixelColor(0xFFE29A))
        canvas.fillRect(x: x + 3 * s, y: base - 9 * s, width: s, height: 2 * s, PixelColor(0xFFE29A))
    }
}
