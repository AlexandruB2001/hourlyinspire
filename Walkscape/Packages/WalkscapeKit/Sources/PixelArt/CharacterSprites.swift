import Foundation
import WalkscapeDomain

/// The little adventurer. One base drawing, recoloured per avatar.
///
/// Frames are composed from an upper body and a set of legs so the walk
/// cycle stays consistent: 0 and 2 are strides, 1 and 3 are passing poses
/// where the body bobs up one pixel.
public enum CharacterSprites {
    public static let width = 16
    public static let height = 20
    public static let walkFrameCount = 4

    public static let basePalette = SpritePalette([
        "o": PixelColor(0x1E2233),   // outline
        "h": PixelColor(0x8A5A3C),   // hair
        "H": PixelColor(0xB07A4F),   // hair highlight
        "d": PixelColor(0x5E3B28),   // hair shade
        "s": PixelColor(0xF2C9A0),   // skin
        "S": PixelColor(0xD9A57E),   // skin shade
        "e": PixelColor(0x1E2233),   // eye
        "c": PixelColor(0xE8907A),   // blush
        "f": PixelColor(0xE3B04B),   // scarf
        "F": PixelColor(0xB9832E),   // scarf shade
        "t": PixelColor(0x4F8A5B),   // tunic
        "T": PixelColor(0x356A44),   // tunic shade
        "l": PixelColor(0x6B4A2F),   // belt
        "p": PixelColor(0x4A5577),   // trousers
        "P": PixelColor(0x363F5C),   // trousers shade (far leg)
        "b": PixelColor(0x6B4A2F),   // boots
        "B": PixelColor(0x4A321F),   // boots shade (far leg)
        "k": PixelColor(0xA0703F),   // backpack
        "K": PixelColor(0x7A5230),   // backpack shade
        "r": PixelColor(0xD8C7A0),   // bedroll
        "w": PixelColor(0xFFF6E0),   // eye shine / highlight
    ])

    /// Colours for an avatar id, including its look's skin tone (see `CharacterLook`).
    public static func palette(for avatarID: String) -> SpritePalette {
        let look = CharacterLook(avatarID: avatarID)
        let colors = colorPalette(for: look.colors)
        guard let skin = look.skin else { return colors }
        return colors.overriding(skinTones[skin.rawValue - 1])
    }

    /// Skin (`s`), skin shade (`S`) and blush (`c`) for each tone, lightest first.
    static let skinTones: [[Character: PixelColor]] = [
        ["s": PixelColor(0xF7D9BC), "S": PixelColor(0xE0B793), "c": PixelColor(0xEC9A86)],
        ["s": PixelColor(0xF2C9A0), "S": PixelColor(0xD9A57E), "c": PixelColor(0xE8907A)],
        ["s": PixelColor(0xD6A27A), "S": PixelColor(0xB8835C), "c": PixelColor(0xD07A62)],
        ["s": PixelColor(0xA8714E), "S": PixelColor(0x8A5A3C), "c": PixelColor(0xB5604E)],
        ["s": PixelColor(0x6E4A34), "S": PixelColor(0x553826), "c": PixelColor(0x8A4A3A)],
    ]

    /// Colour variants for the starter avatars.
    static func colorPalette(for avatarID: String) -> SpritePalette {
        let variants: [String: [Character: PixelColor]] = [
            "fern": [:],
            "sky": ["t": PixelColor(0x4D7FB0), "T": PixelColor(0x37608A), "f": PixelColor(0xF4EBD0), "F": PixelColor(0xC9BC98),
                    "h": PixelColor(0x2E2A2A), "H": PixelColor(0x4A4340), "d": PixelColor(0x1F1B1B)],
            "ember": ["t": PixelColor(0xC0583E), "T": PixelColor(0x93402D), "f": PixelColor(0x4F8A5B), "F": PixelColor(0x356A44),
                      "h": PixelColor(0xD08A3A), "H": PixelColor(0xE9AE5C), "d": PixelColor(0xA0652A),
                      "s": PixelColor(0xE8B88E), "S": PixelColor(0xC9946C)],
            "plum": ["t": PixelColor(0x7D5A9E), "T": PixelColor(0x5D4178), "f": PixelColor(0xE3B04B), "F": PixelColor(0xB9832E),
                     "h": PixelColor(0x3A2A44), "H": PixelColor(0x57406A), "d": PixelColor(0x261B2E),
                     "s": PixelColor(0xA8714E), "S": PixelColor(0x8A5A3C), "c": PixelColor(0xB5604E)],
            "sunny": ["t": PixelColor(0xE3B04B), "T": PixelColor(0xB9832E), "f": PixelColor(0xC0583E), "F": PixelColor(0x93402D),
                      "h": PixelColor(0xF0D27A), "H": PixelColor(0xFFF0B0), "d": PixelColor(0xC9A54E)],
            "frost": ["t": PixelColor(0x8FC3C9), "T": PixelColor(0x6497A0), "f": PixelColor(0x4D7FB0), "F": PixelColor(0x37608A),
                      "h": PixelColor(0xE8EEF2), "H": PixelColor(0xFFFFFF), "d": PixelColor(0xB9C4CC),
                      "s": PixelColor(0x6E4A34), "S": PixelColor(0x553826), "c": PixelColor(0x8A4A3A)],
        ]
        return basePalette.overriding(variants[avatarID] ?? [:])
    }

    static let upperBody = [
        "................",
        ".....oooooo.....",
        "....oHHhhhhoo...",
        "...oHhhhhhhhho..",
        "..ohhhhhhhhhhho.",
        "..ohhhhhhhshhho.",
        "..ohhhhsssssso..",
        "..odhhssswesso..",
        "..odhhsssesso...",
        "...oddsccsso....",
        "....oossssoo....",
        "...okkoffffFo...",
        "..okrkottttTso..",
        "..okKkottttTSo..",
        "..okKkollllloo..",
        "...oooopppppo...",
    ]

    static let legs: [[String]] = [
        [ // stride
            "...oppoopppo....",
            "..oPPo..oppo....",
            "..oBBo...obbo...",
            "..ooo....oooo...",
        ],
        [ // passing (body bobs up, so legs get one extra row)
            ".....oppppo.....",
            ".....oPppo......",
            ".....oPppo......",
            ".....oBbbbo.....",
            ".....oooooo.....",
        ],
        [ // stride, other foot forward
            "...opppoPPo.....",
            "...oppo..oPPo...",
            "..obbo...oBBo...",
            "..oooo....ooo...",
        ],
        [ // passing
            ".....oppppo.....",
            "......opppo.....",
            "......oppPo.....",
            ".....obbbBo.....",
            ".....oooooo.....",
        ],
    ]

    static let idleLegs = [
        "....oppppo......",
        "....opo.opo.....",
        "....obbooobbo...",
        "....oooo.oooo...",
    ]

    /// Walk frame `index` (wraps), facing right, 16x20, transparent background.
    public static func walkFrame(_ index: Int, avatarID: String) -> PixelCanvas {
        let frame = ((index % walkFrameCount) + walkFrameCount) % walkFrameCount
        let bob = frame % 2 == 1 ? -1 : 0
        return compose(legs: legs[frame], bob: bob, palette: palette(for: avatarID), look: CharacterLook(avatarID: avatarID))
    }

    public static func idleFrame(avatarID: String) -> PixelCanvas {
        compose(legs: idleLegs, bob: 0, palette: palette(for: avatarID), look: CharacterLook(avatarID: avatarID))
    }

    /// Head and shoulders for indicators and avatars (16x12).
    public static func portrait(avatarID: String) -> PixelCanvas {
        let palette = palette(for: avatarID)
        let sprite = Sprite(name: "portrait", palette: palette, rows: Array(upperBody.prefix(12)))
        var canvas = sprite.render()
        if let hair = hairOverlays[CharacterLook(avatarID: avatarID).hair] {
            canvas.draw(Sprite(name: "hair", palette: palette, rows: hair.rows), x: hair.x, y: hair.y)
        }
        return canvas
    }

    /// The portrait with worn items (hats, glasses, scarves): the head and
    /// shoulders of the dressed walker, with headroom for a hat (16x16).
    public static func portrait(avatarID: String, outfit: [String]) -> PixelCanvas {
        guard outfit.contains(where: { EquipmentArt.art(for: $0) != nil }) else { return portrait(avatarID: avatarID) }
        let dressed = idleFrame(avatarID: avatarID, outfit: outfit)
        let bodyY = outfittedHeight - idleLegs.count - upperBody.count + 1
        var canvas = PixelCanvas(width: width, height: 12 + outfitHeadroom)
        canvas.draw(dressed, x: 0, y: outfitHeadroom - bodyY)
        return canvas
    }

    // MARK: Looks

    /// Hairstyles drawn over the body in body coordinates (the body palette's
    /// hair colours, so every colour set and dye works).
    static let hairOverlays: [HairStyle: (x: Int, y: Int, rows: [String])] = [
        .pigtails: (0, 4, [
            "..o",
            ".oc",
            "ohh",
            "ohH",
            "ohh",
            "odh",
            ".oo",
        ]),
        .long: (2, 6, [
            "ohh",
            "ohH",
            "ohh",
            "odh",
            "ohd",
            ".oo",
        ]),
        .bun: (5, -1, [
            "..oo..",
            ".ohHo.",
        ]),
        .spiky: (4, -1, [
            "..o.o.o.",
            ".ohohoho",
        ]),
    ]

    /// A short dress over the top of the legs, in tunic colours.
    static let dressOverlay: (x: Int, y: Int, rows: [String]) = (2, 15, [
        "..ottttttTo.",
        ".otttttttTTo",
    ])

    // MARK: Outfits

    /// Extra rows above the head so hats fit. Outfitted frames are
    /// `width` x `outfittedHeight`, with the feet on the bottom row as usual.
    public static let outfitHeadroom = 4
    public static var outfittedHeight: Int { height + outfitHeadroom }

    /// Walk frame wearing shop items (see `EquipmentArt`). Unknown ids are ignored.
    public static func walkFrame(_ index: Int, avatarID: String, outfit: [String]) -> PixelCanvas {
        let frame = ((index % walkFrameCount) + walkFrameCount) % walkFrameCount
        let bob = frame % 2 == 1 ? -1 : 0
        return compose(legs: legs[frame], bob: bob, palette: palette(for: avatarID), look: CharacterLook(avatarID: avatarID), outfit: outfit,
                       canvasHeight: outfittedHeight)
    }

    public static func idleFrame(avatarID: String, outfit: [String]) -> PixelCanvas {
        compose(legs: idleLegs, bob: 0, palette: palette(for: avatarID), look: CharacterLook(avatarID: avatarID), outfit: outfit,
                       canvasHeight: outfittedHeight)
    }

    private static func compose(legs: [String], bob: Int, palette: SpritePalette, look: CharacterLook = CharacterLook(),
                                outfit: [String] = [], canvasHeight: Int = height) -> PixelCanvas {
        let pieces = outfit.compactMap(EquipmentArt.art(for:))
        var palette = palette
        for piece in pieces where !piece.recolor.isEmpty { palette = palette.overriding(piece.recolor) }

        var canvas = PixelCanvas(width: width, height: canvasHeight)
        let body = Sprite(name: "body", palette: palette, rows: upperBody)
        let legSprite = Sprite(name: "legs", palette: palette, rows: legs)
        let bodyY = canvasHeight - legs.count - upperBody.count + 1 + bob
        canvas.draw(legSprite, x: 0, y: canvasHeight - legs.count)
        if look.body == .shorts {
            // Bare lower legs: trouser pixels below the top row become skin.
            for (y, row) in legs.enumerated() where y >= 1 {
                for (x, c) in row.enumerated() where c == "p" || c == "P" {
                    if let skin = palette[c == "p" ? "s" : "S"] { canvas.plot(x, canvasHeight - legs.count + y, skin) }
                }
            }
        }
        canvas.draw(body, x: 0, y: bodyY)
        if let hair = hairOverlays[look.hair] {
            canvas.draw(Sprite(name: "hair", palette: palette, rows: hair.rows), x: hair.x, y: bodyY + hair.y)
        }
        if look.body == .dress {
            canvas.draw(Sprite(name: "dress", palette: palette, rows: dressOverlay.rows), x: dressOverlay.x, y: bodyY + dressOverlay.y)
        }
        for piece in pieces where !piece.overlay.isEmpty {
            let sprite = Sprite(name: "equipment", palette: EquipmentArt.palette, rows: piece.overlay)
            canvas.draw(sprite, x: piece.x, y: bodyY + piece.y)
        }
        if let shoe = pieces.compactMap(\.shoe).last {
            drawShoes(shoe, legs: legs, top: canvasHeight - legs.count, on: &canvas)
        }
        return canvas
    }

    /// Colours the foot pixels (`b` near, `B` far), the outline under them as
    /// the sole, and the trouser pixels just above them as a boot cuff.
    private static func drawShoes(_ shoe: EquipmentArt.Shoe, legs: [String], top: Int, on canvas: inout PixelCanvas) {
        let rows = legs.map(Array.init)
        func char(_ x: Int, _ y: Int) -> Character? {
            guard y >= 0, y < rows.count, x >= 0, x < rows[y].count else { return nil }
            return rows[y][x]
        }
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == "b" || c == "B" {
                canvas.plot(x, top + y, c == "b" ? shoe.upper : shoe.upperFar)
                if let sole = shoe.sole, char(x, y + 1) == "o" {
                    let accent = shoe.soleAccent.flatMap { x % 2 == 0 ? $0 : nil }
                    canvas.plot(x, top + y + 1, accent ?? sole)
                }
                if let cuff = shoe.cuff, let above = char(x, y - 1), "pP".contains(above) {
                    canvas.plot(x, top + y - 1, above == "p" ? cuff : cuff.mixed(with: PixelColor(0x1E2233), 0.25))
                }
            }
        }
    }
}
