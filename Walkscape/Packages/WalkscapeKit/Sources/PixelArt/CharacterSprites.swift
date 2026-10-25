import Foundation

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

    /// Colour variants for the starter avatars.
    public static func palette(for avatarID: String) -> SpritePalette {
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
        return compose(legs: legs[frame], bob: bob, palette: palette(for: avatarID))
    }

    public static func idleFrame(avatarID: String) -> PixelCanvas {
        compose(legs: idleLegs, bob: 0, palette: palette(for: avatarID))
    }

    /// Head and shoulders for indicators and avatars (16x12).
    public static func portrait(avatarID: String) -> PixelCanvas {
        let sprite = Sprite(name: "portrait", palette: palette(for: avatarID), rows: Array(upperBody.prefix(12)))
        return sprite.render()
    }

    private static func compose(legs: [String], bob: Int, palette: SpritePalette) -> PixelCanvas {
        var canvas = PixelCanvas(width: width, height: height)
        let body = Sprite(name: "body", palette: palette, rows: upperBody)
        let legSprite = Sprite(name: "legs", palette: palette, rows: legs)
        canvas.draw(legSprite, x: 0, y: height - legs.count)
        canvas.draw(body, x: 0, y: height - legs.count - upperBody.count + 1 + bob)
        return canvas
    }
}
