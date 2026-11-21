import Foundation
import WalkscapeDomain

/// Pixel art for companions. Each species has one drawing per stage (they
/// grow from 10 to 16 pixels across) plus a list of small details that
/// appear one per kilometre walked within that stage. Elders reuse the
/// guardian drawing with every detail and a soft glow.
public enum CompanionSprites {
    /// Every companion fits in this square, feet on the bottom row.
    public static let canvasSize = 20

    struct StageArt {
        let rows: [String]
        let details: [(x: Int, y: Int, key: Character)]
    }

    static let glow: [String: PixelColor] = [
        "mossling": PixelColor(0x7FE0E8, alpha: 70),
        "emberfox": PixelColor(0xFFB060, alpha: 80),
        "moonmoth": PixelColor(0xC8B4F0, alpha: 80),
    ]

    /// The companion at `growth`, centred at the bottom of a `canvasSize` square.
    public static func render(speciesID: String, growth: CompanionGrowth, accessories: [String] = [],
                              skin: CompanionSkin? = nil) -> PixelCanvas {
        var canvas = PixelCanvas(width: canvasSize, height: canvasSize)
        guard let stages = art[speciesID] else { return canvas }
        let isElder = growth.stage == .elder
        let stageIndex = min(growth.stage.rawValue, stages.count - 1)
        let stage = stages[stageIndex]
        var rows = stage.rows.map { Array($0) }
        let shown = isElder ? stage.details.count : min(stage.details.count, growth.kilometresIntoStage)
        for detail in stage.details.prefix(shown) where rows.indices.contains(detail.y) && rows[detail.y].indices.contains(detail.x) {
            rows[detail.y][detail.x] = detail.key
        }
        var palette = ItemSprites.palette.overriding(["e": PixelColor(0xFF8A3D)])
        if let skin, skin.colors.count >= 3 {
            // Skins recolour each species' body, shading and highlight keys.
            let body = PixelColor(skin.colors[0]), shade = PixelColor(skin.colors[1]), accent = PixelColor(skin.colors[2])
            var overrides: [Character: PixelColor] = [:]
            for key in "gavsnb" { overrides[key] = body }
            for key in "GAVSNB" { overrides[key] = shade }
            for key in "Lhlk" { overrides[key] = accent }
            palette = palette.overriding(overrides)
        }
        let sprite = Sprite(name: speciesID, palette: palette, rows: rows.map { String($0) })
        let x = (canvasSize - sprite.width) / 2
        let y = canvasSize - sprite.height
        if isElder, let glow = glow[speciesID] {
            canvas.fillEllipse(cx: canvasSize / 2, cy: y + sprite.height / 2, rx: sprite.width / 2 + 2,
                               ry: sprite.height / 2 + 2, glow)
        }
        // Accessories sit on the drawing's outline, so they fit every species and stage.
        let opaque = sprite.rows.enumerated().flatMap { row, keys in
            keys.enumerated().compactMap { column, key in key == "." ? nil : (column, row) }
        }
        let top = y + (opaque.map(\.1).min() ?? 0)
        let bottom = y + (opaque.map(\.1).max() ?? sprite.height - 1)
        let left = x + (opaque.map(\.0).min() ?? 0)
        let centre = x + sprite.width / 2
        let worn = accessories.compactMap { id in CompanionAccessoryArt.sprite(id).map { (id, $0) } }
        // Back pieces go first, so the body covers them and they read as worn behind the pet.
        for (id, piece) in worn where CompanionAccessoryArt.slot(of: id) == .back {
            if let colors = CompanionAccessoryArt.capeColors[id] {
                drawCape(on: &canvas, sprite: sprite, x: x, y: y, from: top + (bottom - top) / 3, to: bottom,
                         centre: centre, colors: colors)
            } else if id == "pet-backpack" {
                drawPack(on: &canvas, sprite: sprite, x: x, y: y, top: top, bottom: bottom, centre: centre)
            } else {
                canvas.draw(piece, x: max(0, left - piece.width + piece.width / 2),
                            y: min(canvasSize - piece.height, top + (bottom - top) / 3))
            }
        }
        canvas.draw(sprite, x: x, y: y)
        if worn.contains(where: { $0.0 == "pet-backpack" }) {
            drawPackStraps(on: &canvas, sprite: sprite, x: x, y: y, top: top, bottom: bottom, centre: centre)
        }
        for (id, piece) in worn {
            switch CompanionAccessoryArt.slot(of: id) {
            case .head: canvas.draw(piece, x: centre - piece.width / 2, y: max(0, top - piece.height + 1))
            case .neck: canvas.draw(piece, x: centre - piece.width / 2, y: top + (bottom - top) * 9 / 20)
            default: break
            }
        }
        return canvas
    }

    /// A cape draped behind the body: from the shoulders down to the feet, following the
    /// body's left edge (mirrored on the right, so a tail doesn't stretch it) and flaring
    /// out by one more pixel towards the bottom. It only ever widens going down.
    static func drawCape(on canvas: inout PixelCanvas, sprite: Sprite, x: Int, y: Int, from start: Int, to end: Int,
                         centre: Int, colors: CompanionAccessoryArt.CapeColors) {
        let palette = ItemSprites.palette
        guard end >= start, let outline = palette["o"], let fill = palette[colors.fill],
              let shade = palette[colors.shade], let light = palette[colors.light] else { return }
        let rows = end - start + 1
        var edge = Int.max
        for (index, row) in (start...end).enumerated() {
            let spriteRow = row - y
            if sprite.rows.indices.contains(spriteRow),
               let first = sprite.rows[spriteRow].firstIndex(where: { $0 != "." }) {
                edge = min(edge, x + first)
            }
            guard edge != .max else { continue }
            let flare = 1 + index * 2 / rows
            let left = max(0, edge - flare)
            let right = min(canvasSize - 1, centre + (centre - edge) - 1 + flare)
            guard left <= right else { continue }
            for column in left...right {
                let color: PixelColor
                if column == left || column == right || row == end {
                    color = outline
                } else if column == left + 1 && index % 3 == 1 {
                    color = light
                } else if column >= right - 1 {
                    color = shade
                } else {
                    color = fill
                }
                canvas.plot(column, row, color)
            }
        }
    }

    /// Rows the backpack covers: from a little below the head down to just above the feet.
    static func packRows(top: Int, bottom: Int) -> ClosedRange<Int> {
        let start = top + (bottom - top) * 2 / 5
        return start...max(start, bottom - 1)
    }

    /// The left edge of the body across the pack's rows (the right is mirrored, so a tail doesn't count).
    static func packEdge(sprite: Sprite, x: Int, y: Int, rows: ClosedRange<Int>) -> Int? {
        let edges = rows.compactMap { row -> Int? in
            guard sprite.rows.indices.contains(row - y) else { return nil }
            return sprite.rows[row - y].firstIndex(where: { $0 != "." }).map { x + $0 }
        }
        return edges.min()
    }

    /// The pets face the viewer, so a backpack sits behind the body and shows two pixels
    /// either side of it, with a flap along the top and a buckle on each side.
    static func drawPack(on canvas: inout PixelCanvas, sprite: Sprite, x: Int, y: Int, top: Int, bottom: Int, centre: Int) {
        let palette = ItemSprites.palette
        let rows = packRows(top: top, bottom: bottom)
        guard let edge = packEdge(sprite: sprite, x: x, y: y, rows: rows),
              let outline = palette["o"], let flap = palette["b"], let shade = palette["B"],
              let fill = palette["n"], let buckle = palette["y"], let buckleShade = palette["Y"] else { return }
        let left = max(0, edge - 2)
        let right = min(canvasSize - 1, centre + (centre - edge) - 1 + 2)
        guard left < right else { return }
        for row in rows {
            for column in left...right {
                let isEndRow = row == rows.lowerBound || row == rows.upperBound
                let isEndColumn = column == left || column == right
                if isEndRow && isEndColumn { continue }
                let color: PixelColor
                if isEndRow || isEndColumn {
                    color = outline
                } else if row == rows.lowerBound + 1 {
                    color = flap
                } else if row == rows.lowerBound + 2 || column >= right - 1 {
                    color = shade
                } else {
                    color = fill
                }
                canvas.plot(column, row, color)
            }
            if row == rows.lowerBound + 3 && row < rows.upperBound {
                canvas.plot(left + 1, row, buckle)
                canvas.plot(right - 1, row, buckleShade)
            }
        }
    }

    /// Two straps down the front of the body, below the face.
    static func drawPackStraps(on canvas: inout PixelCanvas, sprite: Sprite, x: Int, y: Int, top: Int, bottom: Int, centre: Int) {
        let rows = packRows(top: top, bottom: bottom)
        guard let edge = packEdge(sprite: sprite, x: x, y: y, rows: rows),
              let strap = ItemSprites.palette["B"], rows.lowerBound + 2 < rows.upperBound else { return }
        let inset = max(2, (centre - edge) / 2)
        for column in [centre - inset - 1, centre + inset] {
            for row in (rows.lowerBound + 2)..<rows.upperBound {
                let spriteRow = row - y, spriteColumn = column - x
                guard sprite.rows.indices.contains(spriteRow) else { continue }
                let keys = Array(sprite.rows[spriteRow])
                guard keys.indices.contains(spriteColumn), keys[spriteColumn] != ".", keys[spriteColumn] != "o" else { continue }
                canvas.plot(column, row, strap)
            }
        }
    }

    public static var speciesIDs: [String] { art.keys.sorted() }

    static let art: [String: [StageArt]] = [
        "mossling": [
            StageArt(rows: [
                "..........",
                "...oooo...",
                "..oWsssoo.",
                ".oWsssssSo",
                ".osowssoSo",
                ".ossssssSo",
                ".oSsssSSSo",
                "..oSSSSSo.",
                "..oo..oo..",
                "..........",
            ], details: [(4, 2, "g"), (5, 2, "L"), (3, 3, "g")]),
            StageArt(rows: [
                "............",
                "....oooo....",
                "...oWWsso...",
                "..oWssssso..",
                ".oWssssssSo.",
                ".osowsssoSo.",
                ".ossssssSSo.",
                "oSosssssSoSo",
                "oSoSsssSSoSo",
                ".ooSSSSSSoo.",
                "..oSSooSSo..",
                "..ooo..ooo..",
            ], details: [(4, 2, "g"), (5, 2, "L"), (6, 2, "g"), (3, 3, "g"), (8, 3, "G"), (2, 4, "g"), (1, 7, "g"), (10, 7, "g"), (5, 6, "c")]),
            StageArt(rows: [
                "..............",
                ".....oooo.....",
                "....oWWsso....",
                "...oWssssso...",
                "..oWsssssssSo.",
                "..osowsssowSo.",
                "..osssssssSSo.",
                ".oSoSsssssSoSo",
                "oSSoSssssSSoSS",
                "oSSoSssssSSoSo",
                ".ooo.SSSSS.oo.",
                "...oSSSSSSSo..",
                "...oSSo.oSSo..",
                "...oooo.oooo..",
            ], details: [(5, 2, "g"), (6, 2, "L"), (7, 2, "g"), (8, 2, "G"), (4, 3, "g"), (9, 3, "L"), (3, 4, "g"), (11, 4, "g"), (1, 8, "g"), (12, 8, "L"), (7, 6, "c"), (6, 8, "c"), (8, 8, "c"), (7, 11, "c")]),
            StageArt(rows: [
                "................",
                "......oooo......",
                ".....oWWsso.....",
                "....oWssssso....",
                "...oWsssssssSo..",
                "...osowssssowSo.",
                "...osssssssssSo.",
                "..oSosssssssSoSo",
                ".oSSoSsssssSSoSS",
                ".oSSoSsssssSSoSS",
                ".oSSoSSsssSSSoSo",
                "..ooo.SSSSSSS.o.",
                "....oSSSSSSSSo..",
                "....oSSSooSSSo..",
                "....oSSo..oSSo..",
                "....oooo..oooo..",
            ], details: [(6, 2, "g"), (7, 2, "L"), (8, 2, "g"), (9, 2, "G"), (5, 3, "g"), (10, 3, "L"), (4, 4, "g"), (12, 4, "g"), (2, 8, "g"), (14, 8, "L"), (2, 9, "G"), (8, 7, "c"), (7, 9, "c"), (9, 9, "c"), (8, 10, "C"), (8, 12, "c"), (6, 13, "g"), (11, 13, "g"), (1, 10, "L"), (15, 9, "g")]),
        ],
        "emberfox": [
            StageArt(rows: [
                "..........",
                ".o....o...",
                ".oao.oao..",
                ".oaaaaao..",
                ".oawaawo..",
                "..oaAaao.o",
                "..owwwaooa",
                "..oaaaaoao",
                "..oo..oo..",
                "..........",
            ], details: [(9, 5, "y"), (9, 6, "h"), (8, 7, "y")]),
            StageArt(rows: [
                "............",
                ".o.....o....",
                ".oao..oao...",
                ".oaaooaao...",
                ".oaaaaaao...",
                ".oawaaawo..o",
                "..oaaAaao.oa",
                "..owwwwaooaa",
                "..oaaaaaoaao",
                "..oaaaaaoAo.",
                "..oo..ooo...",
                "............",
            ], details: [(11, 5, "y"), (11, 6, "e"), (10, 6, "y"), (11, 7, "h"), (2, 3, "e"), (7, 3, "e"), (4, 8, "y")]),
            StageArt(rows: [
                "..............",
                "..o......o....",
                "..oao...oao...",
                "..oaao.oaao...",
                "..oaaaaaaao...",
                "..oawaaaawo.oo",
                "...oaaAaaaooaa",
                "...owwwwaao.aa",
                "...oaaaaaaooaa",
                "...oaaaaaaoaao",
                "...oaAaaAaoAo.",
                "...oao..oao...",
                "...ooo..ooo...",
                "..............",
            ], details: [(12, 5, "y"), (13, 5, "e"), (12, 6, "e"), (13, 6, "h"), (13, 7, "y"), (3, 3, "e"), (9, 3, "e"), (3, 1, "y"), (9, 1, "y"), (6, 9, "y"), (12, 4, "h")]),
            StageArt(rows: [
                "................",
                "...o.......o....",
                "...oao....oao...",
                "...oaao..oaao...",
                "...oaaaaaaaao...",
                "...oawaaaaawo.o.",
                "....oaaAaaaao.oa",
                "....owwwwaaaooaa",
                "....oaaaaaaaoaaa",
                "....oaaaaaaaoaao",
                "....oaaaaaaaoaao",
                "....oaAaaaAaaAo.",
                "....oao...oao...",
                "....oao...oao...",
                "....ooo...ooo...",
                "................",
            ], details: [(14, 5, "y"), (15, 5, "e"), (14, 4, "h"), (15, 6, "h"), (14, 6, "e"), (15, 7, "y"), (4, 3, "e"), (11, 3, "e"), (4, 1, "y"), (11, 1, "y"), (3, 0, "e"), (12, 0, "e"), (7, 9, "y"), (8, 10, "y"), (6, 10, "e"), (13, 9, "h")]),
        ],
        "moonmoth": [
            StageArt(rows: [
                "..........",
                "...o..o...",
                "....oo....",
                ".ooowwooo.",
                "olloVVolll",
                "olvlVVlvlo",
                ".oolooloo.",
                "...oVVo...",
                "....oo....",
                "..........",
            ], details: [(2, 4, "k"), (7, 4, "k"), (2, 5, "c")]),
            StageArt(rows: [
                "............",
                "....o..o....",
                ".....oo.....",
                ".ooo.ww.ooo.",
                "ollloVVolllo",
                "olvllVVllvlo",
                "ollvlVVlvllo",
                ".olllVVlllo.",
                "..oolVVloo..",
                "....oVVo....",
                ".....oo.....",
                "............",
            ], details: [(2, 4, "k"), (9, 4, "k"), (3, 6, "c"), (8, 6, "c"), (1, 5, "w"), (10, 5, "w"), (4, 1, "l")]),
            StageArt(rows: [
                "..............",
                ".....o..o.....",
                "......oo......",
                ".oooo.ww.oooo.",
                "ollllo..ollllo",
                "olvlllVVlllvlo",
                "ollvllVVllvllo",
                "olllvlVVlvlllo",
                ".olllllVVllllo",
                "..oolllVVllo..",
                "...olvlVVlvo..",
                "....oolVVoo...",
                "......oVo.....",
                ".......o......",
            ], details: [(2, 5, "k"), (11, 5, "k"), (3, 7, "c"), (10, 7, "c"), (1, 6, "w"), (12, 6, "w"), (5, 10, "k"), (9, 10, "k"), (5, 1, "l"), (8, 1, "l"), (4, 4, "w"), (9, 4, "w")]),
            StageArt(rows: [
                "................",
                "......o..o......",
                ".......oo.......",
                ".ooooo.ww.ooooo.",
                "olllllo..olllllo",
                "olvllllVVllllvlo",
                "ollvlllVVlllvllo",
                "olllvllVVllvlllo",
                "ollllvlVVlvllllo",
                ".olllllVVlllllo.",
                "..ooollVVlloo...",
                "...olvllVVlvlo..",
                "...ollvlVVvllo..",
                "....oolllVVoo...",
                "......ooVVo.....",
                "........o.......",
            ], details: [(2, 5, "k"), (13, 5, "k"), (3, 7, "c"), (12, 7, "c"), (1, 6, "w"), (14, 6, "w"), (4, 8, "k"), (11, 8, "k"), (6, 1, "l"), (9, 1, "l"), (5, 4, "w"), (10, 4, "w"), (5, 12, "c"), (10, 12, "c"), (2, 4, "c"), (13, 4, "c")]),
        ],
    ]
}
