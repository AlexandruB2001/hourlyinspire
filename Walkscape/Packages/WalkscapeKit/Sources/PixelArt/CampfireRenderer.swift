import Foundation
import WalkscapeDomain

/// The team campsite at night: it gains a tent, benches, cabins and finally
/// a lodge as the Campfire level rises, plus the decorations members placed.
/// `frame` (0...2) animates the flames.
public enum CampfireRenderer {
    public static let width = 120
    public static let height = 64

    static let c = (
        skyTop: PixelColor(0x14213A), skyLow: PixelColor(0x2B3F5E), star: PixelColor(0xFFF6E0),
        hill: PixelColor(0x1F3A33), grass: PixelColor(0x2F5A3E), grassLight: PixelColor(0x3E7A50),
        dirt: PixelColor(0x5B4632), wood: PixelColor(0x8A5A36), woodDark: PixelColor(0x5B3A22),
        canvas: PixelColor(0xD9C9A3), canvasShade: PixelColor(0xB5A07A), flameA: PixelColor(0xFFD25A),
        flameB: PixelColor(0xFF8A3D), flameC: PixelColor(0xE0502E), glow: PixelColor(0xFFB060, alpha: 60),
        stone: PixelColor(0x7A828C), ink: PixelColor(0x1E2233), window: PixelColor(0xFFE59A),
        red: PixelColor(0xC0583E), blue: PixelColor(0x4D7FB0), yellow: PixelColor(0xE3B04B),
        pink: PixelColor(0xF2B7A8), white: PixelColor(0xFFF6E0), green: PixelColor(0x9BD27A), orange: PixelColor(0xE8893A)
    )

    public static func render(level: Int, decorations: [String], frame: Int = 0) -> PixelCanvas {
        var canvas = PixelCanvas(width: width, height: height)
        let ground = 46
        // Sky and stars.
        for y in 0..<ground {
            let color = c.skyTop.mixed(with: c.skyLow, Double(y) / Double(ground))
            canvas.hline(x: 0, y: y, length: width, color)
        }
        var seed: UInt64 = 0x51F2_AA01
        for _ in 0..<26 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            canvas.plot(Int(seed >> 33) % width, Int(seed >> 45) % 30, c.star.withAlpha(UInt8(140 + Int(seed >> 59))))
        }
        // Hills and ground.
        for x in 0..<width {
            let top = 38 + Int(3 * sin(Double(x) / 11) + 2 * sin(Double(x) / 5))
            canvas.vline(x: x, y: top, length: ground - top, c.hill)
        }
        canvas.fillRect(x: 0, y: ground, width: width, height: height - ground, c.grass)
        for x in stride(from: 1, to: width, by: 4) { canvas.plot(x, ground, c.grassLight) }
        canvas.fillEllipse(cx: 60, cy: 54, rx: 20, ry: 5, c.dirt)

        if level >= 5 { lodge(&canvas, ground: ground) }
        if level >= 4 { cabins(&canvas, ground: ground) }
        if level >= 2 { tent(&canvas, ground: ground) }
        if level >= 3 { benches(&canvas) }

        campfire(&canvas, frame: frame)
        for (slot, id) in decorations.prefix(CampfireCatalog.maxPlaced).enumerated() {
            decoration(&canvas, id: id, slot: slot, frame: frame)
        }
        return canvas
    }

    // MARK: Buildings

    static func campfire(_ canvas: inout PixelCanvas, frame: Int) {
        canvas.fillEllipse(cx: 60, cy: 50, rx: 14, ry: 8, c.glow)
        for (x, y) in [(54, 54), (57, 55), (60, 55), (63, 55), (66, 54)] { canvas.fillRect(x: x, y: y, width: 2, height: 2, c.stone) }
        canvas.fillRect(x: 55, y: 53, width: 11, height: 2, c.woodDark)
        canvas.fillRect(x: 57, y: 52, width: 7, height: 1, c.wood)
        let sway = [0, 1, -1][frame % 3]
        canvas.fillRect(x: 57 + sway, y: 47, width: 7, height: 5, c.flameC)
        canvas.fillRect(x: 58, y: 45 + (frame % 2), width: 5, height: 6, c.flameB)
        canvas.fillRect(x: 59 - sway, y: 44, width: 3, height: 6, c.flameA)
        canvas.plot(60 + sway, 42 - (frame % 2), c.flameA)
        // A log to sit on.
        canvas.fillRect(x: 40, y: 55, width: 9, height: 3, c.wood)
        canvas.hline(x: 40, y: 55, length: 9, c.woodDark)
    }

    static func tent(_ canvas: inout PixelCanvas, ground: Int) {
        for row in 0..<12 {
            let half = row
            canvas.hline(x: 24 - half, y: 40 + row, length: half * 2 + 1, row % 3 == 0 ? c.canvasShade : c.canvas)
        }
        canvas.vline(x: 24, y: 41, length: 11, c.canvasShade)
        canvas.fillRect(x: 23, y: 46, width: 3, height: 6, c.ink)
        // Lantern on a pole.
        canvas.vline(x: 36, y: 40, length: 12, c.woodDark)
        canvas.fillRect(x: 35, y: 39, width: 3, height: 3, c.window)
        canvas.fillEllipse(cx: 36, cy: 40, rx: 4, ry: 4, PixelColor(0xFFE59A, alpha: 50))
    }

    static func benches(_ canvas: inout PixelCanvas) {
        for x in [70, 82] {
            canvas.fillRect(x: x, y: 56, width: 9, height: 2, c.wood)
            canvas.vline(x: x + 1, y: 58, length: 2, c.woodDark)
            canvas.vline(x: x + 7, y: 58, length: 2, c.woodDark)
        }
        // Bunting across the camp.
        let colors = [c.red, c.yellow, c.blue, c.pink]
        for (i, x) in stride(from: 30, to: 92, by: 6).enumerated() {
            let y = 30 + Int(3 * sin(Double(x - 30) / 62 * .pi))
            canvas.plot(x, y, c.ink)
            canvas.fillRect(x: x + 1, y: y + 1, width: 2, height: 2, colors[i % colors.count])
        }
        // Cooking pot.
        canvas.fillRect(x: 68, y: 50, width: 5, height: 3, c.ink)
        canvas.hline(x: 67, y: 50, length: 7, c.stone)
    }

    static func cabins(_ canvas: inout PixelCanvas, ground: Int) {
        for x in [84, 100] {
            canvas.fillRect(x: x, y: 36, width: 12, height: 10, c.woodDark)
            for row in 0..<5 { canvas.hline(x: x - 1 + row, y: 31 + row, length: 14 - row * 2, c.red) }
            canvas.fillRect(x: x + 2, y: 39, width: 3, height: 3, c.window)
            canvas.fillRect(x: x + 7, y: 40, width: 3, height: 6, c.ink)
        }
        // Lookout.
        canvas.vline(x: 8, y: 22, length: 24, c.woodDark)
        canvas.vline(x: 14, y: 22, length: 24, c.woodDark)
        canvas.fillRect(x: 6, y: 20, width: 11, height: 3, c.wood)
        canvas.fillRect(x: 7, y: 16, width: 9, height: 4, c.canvasShade)
    }

    static func lodge(_ canvas: inout PixelCanvas, ground: Int) {
        canvas.fillRect(x: 42, y: 24, width: 36, height: 14, c.wood)
        for row in 0..<9 { canvas.hline(x: 39 + row, y: 15 + row, length: 42 - row * 2, c.woodDark) }
        for x in stride(from: 45, to: 76, by: 7) { canvas.fillRect(x: x, y: 28, width: 4, height: 4, c.window) }
        for (x, color) in [(38, c.blue), (80, c.red)] {
            canvas.vline(x: x, y: 10, length: 28, c.woodDark)
            canvas.fillRect(x: x + 1, y: 10, width: 5, height: 7, color)
        }
    }

    // MARK: Decorations

    /// Fixed spots along the front of the camp.
    static let slots = [(6, 58), (20, 58), (32, 57), (90, 57), (102, 58), (112, 58)]

    static func decoration(_ canvas: inout PixelCanvas, id: String, slot: Int, frame: Int) {
        let (x, y) = slots[slot % slots.count]
        switch id {
        case "flowers":
            for (dx, color) in [(0, c.pink), (3, c.yellow), (6, c.white)] {
                canvas.vline(x: x + dx, y: y + 1, length: 2, c.grassLight)
                canvas.plot(x + dx, y, color)
            }
        case "mushrooms":
            for dx in [0, 4] {
                canvas.fillRect(x: x + dx, y: y, width: 3, height: 1, c.red)
                canvas.plot(x + dx + 1, y + 1, c.white)
            }
        case "lantern":
            canvas.vline(x: x + 2, y: y - 8, length: 10, c.woodDark)
            canvas.fillRect(x: x + 1, y: y - 9, width: 3, height: 3, c.window)
        case "signpost":
            canvas.vline(x: x + 2, y: y - 6, length: 8, c.woodDark)
            canvas.fillRect(x: x, y: y - 6, width: 7, height: 2, c.wood)
        case "bunting":
            for i in 0..<4 { canvas.plot(x + i * 2, y - 6 + i % 2, [c.red, c.yellow, c.blue, c.pink][i]) }
        case "pumpkins":
            canvas.fillRect(x: x, y: y, width: 4, height: 3, c.orange)
            canvas.fillRect(x: x + 5, y: y + 1, width: 3, height: 2, c.orange)
            canvas.plot(x + 1, y - 1, c.grassLight)
        case "fireflies":
            canvas.fillRect(x: x, y: y - 3, width: 3, height: 4, c.stone.withAlpha(150))
            canvas.plot(x + 1, y - 2 + frame % 2, c.window)
            canvas.plot(x + 4, y - 7 - frame % 3, c.window)
        case "totem":
            canvas.fillRect(x: x + 1, y: y - 9, width: 4, height: 11, c.wood)
            canvas.plot(x + 2, y - 7, c.ink)
            canvas.plot(x + 3, y - 4, c.red)
        case "banner":
            canvas.vline(x: x, y: y - 12, length: 14, c.woodDark)
            canvas.fillRect(x: x + 1, y: y - 12, width: 5, height: 6, c.yellow)
            canvas.plot(x + 3, y - 10, c.red)
        case "telescope":
            canvas.vline(x: x + 2, y: y - 2, length: 4, c.woodDark)
            canvas.fillRect(x: x, y: y - 5, width: 6, height: 2, c.stone)
        default:
            break
        }
    }
}
