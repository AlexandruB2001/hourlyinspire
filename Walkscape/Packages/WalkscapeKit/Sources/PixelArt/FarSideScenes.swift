import Foundation
import WalkscapeDomain

// Scenes for kilometres 10–20: over the Summit and down the far side to the sea.
// Colour scripts live with the others in `BiomeStyle`.

extension ScenePainter {
    // MARK: Starlight pass

    mutating func paintStarlightPass(_ clouds: inout PixelCanvas, _ far: inout PixelCanvas, _ mid: inout PixelCanvas,
                                     _ ground: inout PixelCanvas, _ style: BiomeStyle, _ footY: Int) {
        // Aurora ribbons on the slow cloud layer, fading upward.
        for (base, color) in [(y(0.16), PixelColor(0x7FF0B8)), (y(0.27), PixelColor(0x8ADCE8))] {
            let shape = terms([(1, 4), (3, 2)])
            for x in 0..<width {
                let center = base + Int(wave(x, shape).rounded())
                let thickness = 5 + Int((2 * sin(2 * .pi * Double(x) * 4 / Double(width))).rounded())
                for k in 0..<thickness {
                    clouds.plot(x, center - k, color.withAlpha(UInt8(max(20, 120 - k * 18))))
                }
                clouds.plot(x, center - thickness, PixelColor(0xE08AD8, alpha: 60))
            }
        }
        let peaks = terms([(2, 8), (5, 3)])
        for x in 0..<width {
            let top = y(0.5) + Int(wave(x, peaks).rounded())
            far.vline(x: x, y: top, length: height - top, PixelColor(0x3A3F6E))
            far.vline(x: x, y: top, length: 2, PixelColor(0xC8D2EE))
        }
        let tops = ridge(&mid, base: y(0.7), spec: [(2, 3), (4, 1.5)], fill: PixelColor(0xD6DEF0), rim: PixelColor(0xF4F7FA))
        for x in positions(count: width / 12, jitter: 3) {
            let wx = ((x % width) + width) % width
            pine(&mid, x: x, base: tops[wx] + 3, height: rng.int(12...18), dark: PixelColor(0x1E3446),
                 light: PixelColor(0x2C4A5E), trunk: PixelColor(0x3A2A20), snow: PixelColor(0xE6EEF8))
        }
        path(&ground, footY: footY, grass: PixelColor(0xDCE4F2), grassDark: PixelColor(0xB4C0DA),
             path: PixelColor(0xA8B4CE), pathDark: PixelColor(0x8A96B4), pathLight: PixelColor(0xC4CEE2))
        // Lanterns guide walkers down the pass.
        for x in stride(from: 14, to: width, by: 36) {
            ground.vline(x: x, y: footY - 10, length: 7, PixelColor(0x3A2A20))
            ground.fillRect(x: x - 1, y: footY - 12, width: 3, height: 2, PixelColor(0xFFD66B))
            ground.fillEllipse(cx: x, cy: footY - 11, rx: 3, ry: 3, PixelColor(0xFFD66B, alpha: 60))
        }
        for _ in 0..<(width / 6) {
            ground.plot(rng.int(0...(width - 1)), rng.int(footY + 5, height - 1), PixelColor(0xB4C0DA))
        }
    }

    // MARK: Hot springs

    mutating func paintHotSprings(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                  _ style: BiomeStyle, _ footY: Int) {
        let peaks = terms([(2, 7), (5, 2)])
        for x in 0..<width {
            let top = y(0.46) + Int(wave(x, peaks).rounded())
            far.vline(x: x, y: top, length: height - top, PixelColor(0x8E9CB8))
            far.vline(x: x, y: top, length: 3, PixelColor(0xF0F4F8))
        }
        let tops = ridge(&mid, base: y(0.66), spec: [(2, 3), (5, 1.5)], fill: PixelColor(0x8A7E70), rim: PixelColor(0xA89C8A))
        // Snow-dusted boulders.
        for x in positions(count: width / 20, jitter: 6) {
            let wx = ((x % width) + width) % width
            let r = rng.int(2...4)
            mid.fillEllipse(cx: x, cy: tops[wx] + 2, rx: r + 1, ry: r, PixelColor(0x6E6458))
            mid.hline(x: x - r + 1, y: tops[wx] + 2 - r, length: r * 2 - 1, PixelColor(0xF0F4F8))
        }
        // Steaming pools set into the rock.
        for x in positions(count: max(2, width / 32), jitter: 5) {
            let wx = ((x % width) + width) % width
            let cy = tops[wx] + 6
            let rx = rng.int(7...10)
            mid.fillEllipse(cx: x, cy: cy, rx: rx + 1, ry: 3, PixelColor(0x6E6458))
            mid.fillEllipse(cx: x, cy: cy, rx: rx, ry: 2, PixelColor(0x6CC8D0))
            mid.hline(x: x - rx + 2, y: cy - 1, length: rx, PixelColor(0xA8E8EC))
            steam(&mid, x: x - 2, top: cy - 14, bottom: cy - 2)
            steam(&mid, x: x + 3, top: cy - 11, bottom: cy - 2)
        }
        path(&ground, footY: footY, grass: PixelColor(0x7E9E64), grassDark: PixelColor(0x627E4C),
             path: PixelColor(0xA8A096), pathDark: PixelColor(0x868076), pathLight: PixelColor(0xC2BCB2))
        // Stepping stones and stone lanterns.
        for x in stride(from: 0, to: width, by: 6) {
            ground.fillRect(x: x + 1, y: footY - 1, width: 4, height: 3, PixelColor(0xBEB8AE))
            ground.hline(x: x + 1, y: footY + 2, length: 4, PixelColor(0x868076))
        }
        for x in stride(from: 20, to: width, by: 48) {
            stoneLantern(&ground, x: x, base: footY - 3)
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 6, color: PixelColor(0x627E4C))
    }

    func steam(_ canvas: inout PixelCanvas, x: Int, top: Int, bottom: Int) {
        guard bottom > top else { return }
        for row in top..<bottom {
            let t = Double(row - top) / Double(bottom - top)
            let sway = Int((2 * sin(Double(row) * 0.6)).rounded())
            let alpha = UInt8(40 + t * 70)
            canvas.plot(x + sway, row, PixelColor(0xFFFFFF, alpha: alpha))
            canvas.plot(x + sway + 1, row, PixelColor(0xFFFFFF, alpha: alpha / 2))
        }
    }

    func stoneLantern(_ canvas: inout PixelCanvas, x: Int, base: Int) {
        let stone = PixelColor(0x9A948A)
        let dark = PixelColor(0x6E6A62)
        canvas.fillRect(x: x - 2, y: base - 1, width: 5, height: 1, dark)
        canvas.fillRect(x: x - 1, y: base - 5, width: 3, height: 4, stone)
        canvas.fillRect(x: x - 2, y: base - 8, width: 5, height: 3, stone)
        canvas.plot(x, base - 7, PixelColor(0xFFD66B))
        canvas.fillRect(x: x - 3, y: base - 9, width: 7, height: 1, dark)
        canvas.plot(x, base - 10, dark)
    }

    // MARK: Maple woods

    mutating func paintAutumnWoods(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                   _ style: BiomeStyle, _ footY: Int) {
        let farTops = ridge(&far, base: y(0.6), spec: [(2, 3), (5, 1)], fill: PixelColor(0xD8B48A), rim: PixelColor(0xE6C8A0))
        for x in positions(count: width / 9, jitter: 3) {
            let wx = ((x % width) + width) % width
            roundTree(&far, x: x, base: farTops[wx] + 1, radius: 3, dark: PixelColor(0xD49A6E), light: PixelColor(0xE4B48A),
                      trunk: PixelColor(0xC08A64))
        }
        let tops = ridge(&mid, base: y(0.7), spec: [(3, 1.5)], fill: PixelColor(0xA8964E), rim: PixelColor(0xC0AC62))
        let leaves = [(PixelColor(0xC0503A), PixelColor(0xE07048)), (PixelColor(0xD8822E), PixelColor(0xF0A848)),
                      (PixelColor(0xD8B032), PixelColor(0xF2D058))]
        for (i, x) in positions(count: max(3, width / 22), jitter: 5).enumerated() {
            let wx = ((x % width) + width) % width
            let leaf = leaves[i % leaves.count]
            roundTree(&mid, x: x, base: tops[wx] + 2, radius: rng.int(4...6), dark: leaf.0, light: leaf.1,
                      trunk: PixelColor(0x5A3E26))
        }
        // A few leaves spinning down.
        for _ in 0..<(width / 16) {
            let leaf = leaves[rng.int(0...2)]
            let lx = rng.int(0...(width - 1))
            let ly = rng.int(y(0.3), y(0.7))
            mid.plot(lx, ly, leaf.1)
            mid.plot(lx + 1, ly + 1, leaf.0)
        }
        path(&ground, footY: footY, grass: PixelColor(0x9AA055), grassDark: PixelColor(0x7E8642),
             path: PixelColor(0xC89E6A), pathDark: PixelColor(0x9E7A4E), pathLight: PixelColor(0xDCB884))
        for _ in 0..<(width / 3) {
            let leaf = leaves[rng.int(0...2)]
            ground.plot(rng.int(0...(width - 1)), rng.int(footY - 4, height - 1), rng.chance(0.5) ? leaf.0 : leaf.1)
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 6, color: PixelColor(0x7E8642))
    }

    // MARK: Bamboo grove

    mutating func paintBambooGrove(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                   _ style: BiomeStyle, _ footY: Int) {
        far.fillRect(x: 0, y: y(0.66), width: width, height: height, PixelColor(0xA6C89A))
        for x in positions(count: width / 4, jitter: 1) {
            bamboo(&far, x: x, bottom: y(0.7), width: 1, color: PixelColor(0xA6C89A), node: PixelColor(0x8EB284))
        }
        mid.fillRect(x: 0, y: y(0.74), width: width, height: height, PixelColor(0x5E8E4A))
        for x in positions(count: width / 7, jitter: 2) {
            bamboo(&mid, x: x, bottom: y(0.76), width: 2, color: PixelColor(0x6FA858), node: PixelColor(0x4E7E3E))
            // Leaf sprays.
            for _ in 0..<3 {
                let ly = rng.int(y(0.05), y(0.5))
                let dir = rng.chance(0.5) ? 1 : -1
                for i in 0..<4 { mid.plot(x + 1 + dir * (i + 1), ly + i / 2, PixelColor(0x5E9E4A)) }
                for i in 0..<3 { mid.plot(x + 1 + dir * (i + 1), ly + i / 2 + 1, PixelColor(0x7FBA5E)) }
            }
        }
        // Soft light through the canopy.
        for x in positions(count: 3, jitter: 10) {
            for row in y(0.1)..<y(0.74) {
                mid.plot(x - (row - y(0.1)) / 4, row, PixelColor(0xF4FFE0, alpha: 35))
                mid.plot(x + 1 - (row - y(0.1)) / 4, row, PixelColor(0xF4FFE0, alpha: 25))
            }
        }
        path(&ground, footY: footY, grass: PixelColor(0x6E9E52), grassDark: PixelColor(0x52803E),
             path: PixelColor(0xC2B28A), pathDark: PixelColor(0x9A8A66), pathLight: PixelColor(0xD8CAA4))
        // New shoots along the path.
        for x in positions(count: width / 14, jitter: 4) {
            ground.vline(x: x, y: footY - 7, length: 4, PixelColor(0x8A7A4E))
            ground.plot(x, footY - 8, PixelColor(0x6FA858))
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 5, color: PixelColor(0x52803E))
    }

    func bamboo(_ canvas: inout PixelCanvas, x: Int, bottom: Int, width w: Int, color: PixelColor, node: PixelColor) {
        canvas.fillRect(x: x, y: 0, width: w, height: bottom, color)
        for row in stride(from: ((x * 7) % 9 + 9) % 9 + 3, to: bottom, by: 9) {
            canvas.hline(x: x, y: row, length: w, node)
        }
    }

    // MARK: Blossom orchard

    mutating func paintBlossomOrchard(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                      _ style: BiomeStyle, _ footY: Int) {
        _ = ridge(&far, base: y(0.6), spec: [(1, 4), (3, 2)], fill: PixelColor(0xB8D4A8), rim: PixelColor(0xCCE2BC))
        let tops = ridge(&mid, base: y(0.7), spec: [(2, 2), (5, 1)], fill: PixelColor(0x8CC070), rim: PixelColor(0xA6D488))
        let petals = [PixelColor(0xF6C4D8), PixelColor(0xFFEAF2), PixelColor(0xE89AB8)]
        for x in positions(count: max(3, width / 26), jitter: 5) {
            let wx = ((x % width) + width) % width
            let base = tops[wx] + 2
            let r = rng.int(5...7)
            mid.fillRect(x: x - 1, y: base - r - 2, width: 2, height: r + 2, PixelColor(0x5A3E3A))
            mid.plot(x + 1, base - r - 1, PixelColor(0x5A3E3A))
            mid.fillEllipse(cx: x, cy: base - r * 2, rx: r + 1, ry: r, PixelColor(0xE89AB8))
            mid.fillEllipse(cx: x - 1, cy: base - r * 2 - 1, rx: r - 1, ry: r - 2, PixelColor(0xF6C4D8))
            for _ in 0..<6 {
                mid.plot(x + rng.int(-r...r), base - r * 2 + rng.int(-r / 2...r / 2), PixelColor(0xFFEAF2))
            }
        }
        // Petals on the breeze.
        for _ in 0..<(width / 10) {
            mid.plot(rng.int(0...(width - 1)), rng.int(y(0.25), y(0.65)), petals[rng.int(0...2)])
        }
        path(&ground, footY: footY, grass: PixelColor(0x86BE64), grassDark: PixelColor(0x669E4C),
             path: PixelColor(0xD8B884), pathDark: PixelColor(0xB0905E), pathLight: PixelColor(0xEAD2A4))
        for _ in 0..<(width / 3) {
            ground.plot(rng.int(0...(width - 1)), rng.int(footY - 4, height - 1), petals[rng.int(0...2)])
        }
        foregroundGrass(&ground, from: footY + 5, count: width / 6, color: PixelColor(0x669E4C))
    }

    // MARK: Lavender fields

    mutating func paintLavenderFields(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                      _ style: BiomeStyle, _ footY: Int) {
        _ = ridge(&far, base: y(0.56), spec: [(1, 4), (2, 2)], fill: PixelColor(0xA8B4D0), rim: PixelColor(0xC0CADE))
        let tops = ridge(&mid, base: y(0.64), spec: [(1, 2), (3, 1)], fill: PixelColor(0x7A9A5A), rim: PixelColor(0x94B070))
        let windmillX = Int(Double(width) * 0.62)
        windmill(&mid, x: windmillX, base: tops[windmillX % width] + 1)
        // Rows of lavender running to the horizon.
        for x in 0..<width {
            for row in stride(from: tops[x] + 2, to: height, by: 1) where (row - tops[x]) % 3 != 0 {
                mid.plot(x, row, (x + row) % 4 == 0 ? PixelColor(0xB49AE0) : PixelColor(0x8E6CC0))
            }
        }
        path(&ground, footY: footY, grass: PixelColor(0x7A9A5A), grassDark: PixelColor(0x5E7E44),
             path: PixelColor(0xDCC294), pathDark: PixelColor(0xB49C6E), pathLight: PixelColor(0xEAD6AE))
        // Lavender spikes along both edges of the path.
        for x in stride(from: 0, to: width, by: 2) {
            let h = rng.int(3...5)
            ground.vline(x: x, y: footY - 4 - h, length: h, PixelColor(0x8E6CC0))
            ground.plot(x, footY - 4 - h, PixelColor(0xB49AE0))
        }
        for _ in 0..<(width / 3) {
            let lx = rng.int(0...(width - 1))
            let ly = rng.int(footY + 5, height - 1)
            ground.vline(x: lx, y: ly - 2, length: 2, PixelColor(0x8E6CC0))
            ground.plot(lx, ly, PixelColor(0x5E7E44))
        }
    }

    func windmill(_ canvas: inout PixelCanvas, x: Int, base: Int) {
        let wall = PixelColor(0xF4EBD0)
        let shade = PixelColor(0xD9CCAA)
        let sail = PixelColor(0xE8DCC0)
        let wood = PixelColor(0x6B4A2F)
        for row in 0..<16 {
            let half = 2 + row / 5
            canvas.hline(x: x - half, y: base - 16 + row, length: half * 2 + 1, wall)
            canvas.plot(x + half, base - 16 + row, shade)
        }
        canvas.fillRect(x: x - 1, y: base - 4, width: 3, height: 4, wood)
        canvas.plot(x, base - 10, PixelColor(0xFFD66B))
        for row in 0..<4 {
            canvas.hline(x: x - row - 1, y: base - 20 + row, length: row * 2 + 3, PixelColor(0x8E3F2C))
        }
        // Four sails on a diagonal cross, each with a slatted edge.
        let hubX = x
        let hubY = base - 18
        for i in 1...9 {
            canvas.plot(hubX + i, hubY - i, wood)
            canvas.plot(hubX - i, hubY + i, wood)
            canvas.plot(hubX + i, hubY + i, wood)
            canvas.plot(hubX - i, hubY - i, wood)
            if i > 2 {
                canvas.plot(hubX + i + 1, hubY - i, sail)
                canvas.plot(hubX - i - 1, hubY + i, sail)
                canvas.plot(hubX + i, hubY + i + 1, sail)
                canvas.plot(hubX - i, hubY - i - 1, sail)
            }
        }
        canvas.plot(hubX, hubY, PixelColor(0x3A2A20))
    }

    // MARK: Red rock canyon

    mutating func paintRedCanyon(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                 _ style: BiomeStyle, _ footY: Int) {
        // Flat-topped mesas with striped rock.
        for x in positions(count: max(2, width / 45), jitter: 8) {
            let w = rng.int(18...30)
            let top = rng.int(y(0.36), y(0.5))
            for row in top..<height {
                let half = w / 2 + (row - top) / 3
                let color = (row - top) % 5 == 4 ? PixelColor(0xB8704C) : PixelColor(0xD08A60)
                far.hline(x: x - half, y: row, length: half * 2, color)
            }
            far.hline(x: x - w / 2, y: top, length: w, PixelColor(0xE8AA78))
        }
        let tops = ridge(&mid, base: y(0.7), spec: [(2, 2), (5, 1)], fill: PixelColor(0xB8683E), rim: PixelColor(0xD4844E))
        for x in positions(count: max(2, width / 30), jitter: 6) {
            let wx = ((x % width) + width) % width
            cactus(&mid, x: x, base: tops[wx] + 2, height: rng.int(8...13))
        }
        path(&ground, footY: footY, grass: PixelColor(0xD49A60), grassDark: PixelColor(0xB87C48),
             path: PixelColor(0xE8C08A), pathDark: PixelColor(0xC49A64), pathLight: PixelColor(0xF4D6A6))
        // Pebbles, and little barrel cacti in flower.
        for _ in 0..<(width / 8) {
            let px = rng.int(0...(width - 1))
            let py = rng.int(footY + 5, height - 2)
            ground.hline(x: px, y: py, length: 2, PixelColor(0x9E5E3A))
            ground.plot(px, py - 1, PixelColor(0xC07848))
        }
        for x in positions(count: width / 20, jitter: 5) {
            ground.fillEllipse(cx: x, cy: footY - 5, rx: 2, ry: 1, PixelColor(0x5E8E4A))
            ground.plot(x, footY - 7, PixelColor(0xF2B7A8))
        }
    }

    func cactus(_ canvas: inout PixelCanvas, x: Int, base: Int, height h: Int) {
        let green = PixelColor(0x5E8E4A)
        let light = PixelColor(0x7FAE5E)
        canvas.fillRect(x: x - 1, y: base - h, width: 3, height: h, green)
        canvas.vline(x: x - 1, y: base - h, length: h, light)
        let armY = base - h * 2 / 3
        canvas.hline(x: x - 4, y: armY, length: 3, green)
        canvas.vline(x: x - 4, y: armY - 4, length: 4, green)
        canvas.hline(x: x + 2, y: armY + 2, length: 3, green)
        canvas.vline(x: x + 4, y: armY - 2, length: 4, green)
    }

    // MARK: Firefly marsh

    mutating func paintFireflyMarsh(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                    _ style: BiomeStyle, _ footY: Int) {
        let tops = ridge(&far, base: y(0.6), spec: [(2, 2), (5, 1)], fill: PixelColor(0x3E4670))
        for x in positions(count: width / 10, jitter: 3) {
            let wx = ((x % width) + width) % width
            roundTree(&far, x: x, base: tops[wx] + 1, radius: rng.int(3...5), dark: PixelColor(0x343C64),
                      light: PixelColor(0x3E4670), trunk: PixelColor(0x343C64))
        }
        let waterTop = y(0.68)
        water(&mid, top: waterTop, bottom: height, base: PixelColor(0x4A5A86), deep: PixelColor(0x3A4874),
              shine: PixelColor(0xD8A0A8), seed: 23)
        for x in positions(count: width / 12, jitter: 4) {
            mid.fillEllipse(cx: x, cy: waterTop + rng.int(2...5), rx: 3, ry: 1, PixelColor(0x4E8A5A))
            if rng.chance(0.4) { mid.plot(x, waterTop + 2, PixelColor(0xF2B7A8)) }
        }
        for x in positions(count: width / 6, jitter: 2) {
            let h = rng.int(6...11)
            mid.vline(x: x, y: waterTop - h + 2, length: h, PixelColor(0x3E6A48))
            mid.vline(x: x, y: waterTop - h, length: 3, PixelColor(0x6B4A2F))
        }
        // Boardwalk on stilts over the water.
        ground.fillRect(x: 0, y: footY - 2, width: width, height: 4, PixelColor(0x8A6A4A))
        ground.hline(x: 0, y: footY - 2, length: width, PixelColor(0xA8845E))
        ground.hline(x: 0, y: footY + 2, length: width, PixelColor(0x4A3A2A))
        for x in stride(from: 0, to: width, by: 5) { ground.vline(x: x, y: footY - 1, length: 3, PixelColor(0x6E5238)) }
        for x in stride(from: 3, to: width, by: 14) {
            ground.fillRect(x: x, y: footY + 3, width: 2, height: 5, PixelColor(0x4A3A2A))
        }
        // Fireflies, some far, some close.
        for _ in 0..<(width / 8) {
            let fx = rng.int(0...(width - 1))
            let fy = rng.int(y(0.35), footY - 4)
            mid.fillEllipse(cx: fx, cy: fy, rx: 2, ry: 2, PixelColor(0xE8F27A, alpha: 45))
            mid.plot(fx, fy, PixelColor(0xF4FFB0))
        }
        for _ in 0..<(width / 14) {
            let fx = rng.int(0...(width - 1))
            let fy = rng.int(footY + 4, height - 2)
            ground.fillEllipse(cx: fx, cy: fy, rx: 2, ry: 2, PixelColor(0xE8F27A, alpha: 60))
            ground.plot(fx, fy, PixelColor(0xF4FFB0))
        }
    }

    // MARK: Sandy shore

    mutating func paintSandyShore(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                  _ style: BiomeStyle, _ footY: Int) {
        let horizon = y(0.58)
        water(&far, top: horizon, bottom: height, base: PixelColor(0x4F9CC8), deep: PixelColor(0x3E86B4),
              shine: PixelColor(0xA8D8F0), seed: 31)
        far.hline(x: 0, y: horizon, length: width, PixelColor(0x8CC4E0))
        // An island and a little sailboat on the horizon.
        let island = Int(Double(width) * 0.3)
        far.fillEllipse(cx: island, cy: horizon, rx: 9, ry: 3, PixelColor(0x6E9EA0))
        far.hline(x: island - 9, y: horizon, length: 19, PixelColor(0x8CC4E0))
        let boat = Int(Double(width) * 0.72)
        far.hline(x: boat - 2, y: horizon - 1, length: 5, PixelColor(0x6B4A2F))
        for row in 0..<5 { far.hline(x: boat, y: horizon - 2 - row, length: max(1, 3 - row / 2), PixelColor(0xFFFBF0)) }
        // Rolling surf over wet sand.
        let surf = terms([(3, 1.5), (7, 0.8)])
        for x in 0..<width {
            let top = y(0.7) + Int(wave(x, surf).rounded())
            mid.vline(x: x, y: top, length: 4, PixelColor(0x6CC4CC))
            mid.plot(x, top, PixelColor(0xF4FBFA))
            if (x / 3) % 2 == 0 { mid.plot(x, top + 1, PixelColor(0xD6F0EE)) }
            mid.vline(x: x, y: top + 4, length: height - top - 4, PixelColor(0xE8D2A0))
            mid.plot(x, top + 4, PixelColor(0xF4FBFA, alpha: 160))
        }
        path(&ground, footY: footY, grass: PixelColor(0xF0D9A0), grassDark: PixelColor(0xDCC088),
             path: PixelColor(0xE6CA90), pathDark: PixelColor(0xC8AA72), pathLight: PixelColor(0xF6E4B8))
        // Dune grass, shells and the odd starfish.
        for x in positions(count: width / 9, jitter: 3) {
            for i in 0..<3 {
                ground.vline(x: x + i * 2 - 2, y: footY - 9 + abs(i - 1), length: 5, PixelColor(0x8AAE5A))
            }
        }
        for _ in 0..<(width / 12) {
            let sx = rng.int(0...(width - 1))
            let sy = rng.int(footY + 5, height - 2)
            if rng.chance(0.3) {
                let star = PixelColor(0xE07848)
                ground.plot(sx, sy, star)
                ground.plot(sx - 1, sy, star)
                ground.plot(sx + 1, sy, star)
                ground.plot(sx, sy - 1, star)
                ground.plot(sx, sy + 1, star)
            } else {
                ground.plot(sx, sy, PixelColor(0xFFF6E0))
                ground.plot(sx + 1, sy, PixelColor(0xF2B7A8))
            }
        }
    }

    // MARK: Lighthouse point

    mutating func paintLighthousePoint(_ far: inout PixelCanvas, _ mid: inout PixelCanvas, _ ground: inout PixelCanvas,
                                       _ style: BiomeStyle, _ footY: Int) {
        let horizon = y(0.6)
        water(&far, top: horizon, bottom: height, base: PixelColor(0x6A78B0), deep: PixelColor(0x56649C),
              shine: PixelColor(0xF6C896), seed: 41)
        // The setting sun's path across the water.
        let sunX = Int(Double(width) * 0.78)
        for row in stride(from: horizon + 1, to: height, by: 2) {
            let spread = (row - horizon) / 2 + 2
            far.hline(x: sunX - spread / 2 + row % 3, y: row, length: max(1, spread / 2), PixelColor(0xFFD890, alpha: 170))
        }
        let tops = ridge(&mid, base: y(0.66), spec: [(1, 3), (3, 1)], fill: PixelColor(0x6E9E52), rim: PixelColor(0x8AB868))
        // Rocky cliff face below the clifftop grass.
        for x in 0..<width {
            mid.vline(x: x, y: tops[x] + 3, length: height - tops[x] - 3,
                      (x / 4) % 2 == 0 ? PixelColor(0x9A8C7A) : PixelColor(0x8A7C6A))
        }
        let lighthouseX = Int(Double(width) * 0.4)
        lighthouse(&mid, x: lighthouseX, base: tops[lighthouseX % width] + 2)
        path(&ground, footY: footY, grass: PixelColor(0x7AAE5E), grassDark: PixelColor(0x5E9248),
             path: PixelColor(0xD8BC88), pathDark: PixelColor(0xB09464), pathLight: PixelColor(0xEAD2A4))
        // Rope fence along the cliff edge.
        for x in stride(from: 4, to: width, by: 10) {
            ground.vline(x: x, y: footY - 10, length: 7, PixelColor(0x8A6238))
        }
        for x in 0..<width {
            let phase = (x + 6) % 10
            ground.plot(x, footY - 9 + (phase >= 3 && phase <= 7 ? 1 : 0), PixelColor(0xD8C8A0))
        }
        meadowFlowers(&ground, footY: footY)
    }

    func lighthouse(_ canvas: inout PixelCanvas, x: Int, base: Int) {
        let dark = PixelColor(0x2E3A4A)
        let towerHeight = 22
        for row in 0..<towerHeight {
            let half = 2 + row / 8
            let stripe = (row / 4) % 2 == 0 ? PixelColor(0xF4EBD0) : PixelColor(0xC0583E)
            let yy = base - towerHeight + row
            canvas.hline(x: x - half, y: yy, length: half * 2 + 1, stripe)
            canvas.plot(x + half, yy, stripe.mixed(with: dark, 0.25))
        }
        let top = base - towerHeight
        // Light beams sweeping out to sea, drawn first so the lamp sits on top.
        for i in 1...18 {
            let spread = i / 3
            canvas.vline(x: x + 2 + i, y: top - 3 - spread, length: spread * 2 + 1,
                         PixelColor(0xFFF1B8, alpha: UInt8(max(10, 90 - i * 4))))
            canvas.vline(x: x - 2 - i, y: top - 3 - spread, length: spread * 2 + 1,
                         PixelColor(0xFFF1B8, alpha: UInt8(max(10, 70 - i * 4))))
        }
        canvas.fillRect(x: x - 3, y: top - 1, width: 7, height: 1, dark)
        canvas.fillRect(x: x - 2, y: top - 5, width: 5, height: 4, PixelColor(0xFFE29A))
        canvas.vline(x: x - 2, y: top - 5, length: 4, dark)
        canvas.vline(x: x + 2, y: top - 5, length: 4, dark)
        for row in 0..<3 { canvas.hline(x: x - row, y: top - 8 + row, length: row * 2 + 1, dark) }
        canvas.fillRect(x: x - 1, y: base - 4, width: 3, height: 4, PixelColor(0x6B4A2F))
    }
}
