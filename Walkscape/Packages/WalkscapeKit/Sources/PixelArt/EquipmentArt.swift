import Foundation

/// How each shop item changes the walker: palette swaps (scarves, packs), an
/// overlay drawn in body coordinates (hats, glasses, scarf tails, capes, wings)
/// and/or a shoe style drawn on the feet of every walk frame.
/// Body coordinates match `CharacterSprites.upperBody`; negative `y` reaches into
/// the headroom above the head.
public struct EquipmentArt: Sendable {
    public let recolor: [Character: PixelColor]
    public let overlay: [String]
    public let x: Int
    public let y: Int
    /// Shoes: drawn on the feet of every frame (see `CharacterSprites.compose`).
    public let shoe: Shoe?

    /// A shoe's look: the upper (near and far foot), an optional sole under the
    /// foot and an optional cuff on the leg above it (boots).
    public struct Shoe: Sendable {
        public let upper: PixelColor
        public let upperFar: PixelColor
        public let sole: PixelColor?
        public let cuff: PixelColor?
        /// Alternating sole colour, e.g. skate wheels.
        public let soleAccent: PixelColor?

        init(_ upper: UInt32, _ upperFar: UInt32, sole: UInt32? = nil, cuff: UInt32? = nil, soleAccent: UInt32? = nil) {
            self.upper = PixelColor(upper)
            self.upperFar = PixelColor(upperFar)
            self.sole = sole.map { PixelColor($0) }
            self.cuff = cuff.map { PixelColor($0) }
            self.soleAccent = soleAccent.map { PixelColor($0) }
        }
    }

    init(recolor: [Character: UInt32] = [:], at position: (Int, Int) = (0, 0), overlay: [String] = [], shoe: Shoe? = nil) {
        self.recolor = recolor.mapValues { PixelColor($0) }
        self.overlay = overlay
        x = position.0
        y = position.1
        self.shoe = shoe
    }

    /// Item palette plus outfit-only colours (`q`/`Q` are see-through glass).
    static let palette = ItemSprites.palette.overriding([
        "x": PixelColor(0x2E3440), "X": PixelColor(0x4A5266),
        "q": PixelColor(0xBFEFF4, alpha: 110), "Q": PixelColor(0x7FE0E8, alpha: 150),
    ])

    public static func art(for itemID: String) -> EquipmentArt? { pieces[itemID] }

    public static var allIDs: [String] { pieces.keys.sorted() }

    static let pieces: [String: EquipmentArt] = [
        "straw-hat": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            "....oooooo....",
            "...oyyyyyyo...",
            "...ohyyyyyo...",
            "...orrrrrro...",
            ".ooyyyyyyyyoo.",
            "oYYYYYYYYYYYYo",
        ]),
        "red-beanie": EquipmentArt(at: (1, -4), overlay: [
            "......oo......",
            ".....owwo.....",
            "......oo......",
            "....orrrro....",
            "...orrrrrro...",
            "..orrrrrrrro..",
            "..oRwRwRwRwo..",
            "..oRRRRRRRRo..",
        ]),
        "bucket-hat": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            "....oooooo....",
            "...oGgggggo...",
            "...oGgggggo.r.",
            "...oGGGGGGoyo.",
            "..oGgggggggGo.",
            "..oooooooooo..",
        ]),
        "trail-cap": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            "..............",
            "....oooooo....",
            "...ouuuuuuo...",
            "...ouuuwuuo...",
            "..ouuuuuuuuooo",
            "..oUUUUUUUUUUo",
        ]),
        "flower-crown": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            "..............",
            "..............",
            "....p...y...p.",
            "...pwpgyhygpwp",
            "...oGGGGGGGGo.",
            "..............",
        ]),
        "top-hat": EquipmentArt(at: (1, -4), overlay: [
            "...oooooooo...",
            "...oxxxxxXo...",
            "...oxxxxxXo...",
            "...oxxxxxXo...",
            "...oxxxxxXo...",
            "...orrrrrro...",
            ".ooxxxxxxxxoo.",
            "oXXXXXXXXXXXXo",
        ]),
        "explorer-helmet": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            ".....oooo.....",
            "...oowwwwoo...",
            "..owwwwwwwwo..",
            "..owwhwwwwwo..",
            ".oBBBBBBBBBBo.",
            "onnnnnnnnnnnno",
        ]),
        "wizard-hat": EquipmentArt(at: (1, -4), overlay: [
            ".........oo...",
            "........ovo...",
            ".......ovvo...",
            "......ovhvo...",
            ".....ovvvvo...",
            "....ovvvhvvo..",
            ".oovvvvvvvvvoo",
            "oVVVhVVVVVhVVo",
        ]),
        "viking-helmet": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "o............o",
            "wo..........ow",
            "wwo.oooooo.oww",
            ".wwoWWWWWWoww.",
            "..ooWssssWoo..",
            "..osssssssso..",
            ".oSSSSSSSSSSo.",
        ]),
        "golden-crown": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            "...o...o...o..",
            "..oho.oho.oho.",
            "..ohyoyhyoyho.",
            "..oyyyyyyyyyo.",
            "..oyryycyyuyo.",
            "..oYYYYYYYYYo.",
        ]),
        "round-glasses": EquipmentArt(at: (5, 6), overlay: [
            "...oooo",
            "ooooqqo",
            "...oqqo",
            "...oooo",
        ]),
        "sunglasses": EquipmentArt(at: (5, 6), overlay: [
            "...oooo",
            "ooooxwo",
            "...oxxo",
            ".......",
        ]),
        "heart-glasses": EquipmentArt(at: (5, 6), overlay: [
            "...m.m.",
            "ooommmm",
            "...mmmm",
            "....mm.",
        ]),
        "cherry-scarf": EquipmentArt(recolor: ["f": 0xC0583E, "F": 0x93402D], at: (9, 12), overlay: [
            "rR",
            "Rr",
            "w.",
        ]),
        "ocean-scarf": EquipmentArt(recolor: ["f": 0x4D7FB0, "F": 0x37608A], at: (9, 12), overlay: [
            "uw",
            "Uu",
            "wU",
        ]),
        "mint-scarf": EquipmentArt(recolor: ["f": 0x9BD27A, "F": 0x5FA05A], at: (9, 12), overlay: [
            "Lg",
            "gL",
            "L.",
        ]),
        "candy-scarf": EquipmentArt(recolor: ["f": 0xF4EBD0, "F": 0xC0583E], at: (9, 12), overlay: [
            "wr",
            "rw",
            "wr",
        ]),
        "sunset-scarf": EquipmentArt(recolor: ["f": 0xE8893A, "F": 0xB5602A], at: (9, 12), overlay: [
            "ya",
            "aA",
            "Ay",
        ]),
        "rainbow-scarf": EquipmentArt(recolor: ["F": 0x9A78D0], at: (7, 11), overlay: [
            "rayg",
            "..ry",
            "..gu",
            "..vr",
        ]),
        "aurora-scarf": EquipmentArt(recolor: ["F": 0xE58AD8], at: (7, 11), overlay: [
            "gLcQ",
            "..cL",
            "..Qm",
            "..lc",
        ]),
        "red-sneakers": EquipmentArt(shoe: .init(0xC0583E, 0x93402D, sole: 0xFFF6E0)),
        "blue-wellies": EquipmentArt(shoe: .init(0x4D7FB0, 0x37608A, sole: 0x2E3440, cuff: 0x4D7FB0)),
        "white-sneakers": EquipmentArt(shoe: .init(0xF4F1E8, 0xC8C4BA, sole: 0xC0583E)),
        "moss-hikers": EquipmentArt(shoe: .init(0x5FA05A, 0x3E7A44, sole: 0x4A321F, cuff: 0xA0703F)),
        "cloud-walkers": EquipmentArt(shoe: .init(0xE8F4FA, 0x8FC3C9, sole: 0xFFFFFF, soleAccent: 0xBFEFF4)),
        "golden-boots": EquipmentArt(shoe: .init(0xE3B04B, 0xB9832E, sole: 0x6B4A2F, cuff: 0xE3B04B)),
        "explorer-pack": EquipmentArt(recolor: ["k": 0x4D7FB0, "K": 0x37608A, "r": 0xE3B04B]),
        "hero-cape": EquipmentArt(at: (0, 10), overlay: [
            "....oo",
            "...orr",
            "..orrr",
            ".orrRr",
            ".orrRr",
            "orrRRo",
            "orRRo.",
            "oooo..",
        ]),
        "fairy-wings": EquipmentArt(at: (0, 8), overlay: [
            ".oo...",
            "oqqo..",
            "oqQqo.",
            ".oqQqo",
            "..oqqo",
            ".oqqo.",
            ".oo...",
        ]),
        "beret": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            "..............",
            "......o.......",
            "....ooooooo...",
            "...ommmmmmmo..",
            "..ommmmmmmmmo.",
            "...oooooooo...",
        ]),
        "cat-beanie": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "...o......o...",
            "..oxo....oxo..",
            "..oxpoooopxo..",
            "..oxxxxxxxxo..",
            "..oxxxxxxxxo..",
            "..oXXXXXXXXo..",
            "..oooooooooo..",
        ]),
        "frog-hat": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "...ooo..ooo...",
            "..owwo.owwo...",
            "..owoooowoo...",
            "..oggggggggo..",
            "..ogLgggggLgo.",
            "..oGGGGGGGGo..",
            "..oooooooooo..",
        ]),
        "halo": EquipmentArt(at: (3, -4), overlay: [
            "..........",
            "..oyyyyo..",
            ".oh....ho.",
            "..oyyyyo..",
        ]),
        "ski-goggles": EquipmentArt(at: (3, 5), overlay: [
            "ooooooooo",
            "uuuuoQQQo",
            "ooooooooo",
        ]),
        "monocle": EquipmentArt(at: (8, 5), overlay: [
            ".ooo",
            "oqqo",
            "oqqo",
            ".ooy",
            "...y",
        ]),
        "star-glasses": EquipmentArt(at: (5, 5), overlay: [
            "....y..",
            "ooo.yyy",
            "...yyy.",
            "....y.y",
        ]),
        "bandana": EquipmentArt(at: (7, 11), overlay: [
            "rRrrR",
            ".rwr.",
            "..r..",
        ]),
        "bow-tie": EquipmentArt(at: (7, 11), overlay: [
            "uo.ou",
            "uuouu",
            "uo.ou",
        ]),
        "flower-lei": EquipmentArt(at: (6, 10), overlay: [
            "p.y.m.",
            "gpygmg",
            ".g.g..",
        ]),
        "bindle": EquipmentArt(at: (0, 3), overlay: [
            ".rRr..",
            "rwrRr.",
            ".rrr..",
            "...n..",
            "....n.",
            ".....n",
            "......",
        ]),
        "turtle-shell": EquipmentArt(at: (0, 10), overlay: [
            ".oooo.",
            "oGgGgo",
            "ogLggo",
            "oGgGgo",
            ".oooo.",
        ]),
        "guitar": EquipmentArt(at: (0, 6), overlay: [
            "on....",
            ".on...",
            "..on..",
            "..oaao",
            ".oaAao",
            ".oaoao",
            ".oaaao",
            "..ooo.",
        ]),
        "yellow-wellies": EquipmentArt(shoe: .init(0xF2C84A, 0xC9A030, sole: 0x2E3440, cuff: 0xF2C84A)),
        "roller-skates": EquipmentArt(shoe: .init(0xF2B7A8, 0xD98A7A, sole: 0x7FE0E8, soleAccent: 0x2E3440)),
        // Seasonal Outfit Bundle (premium, never in the coin shop).
        "harvest-crown": EquipmentArt(at: (1, -4), overlay: [
            "..............",
            "..............",
            "..............",
            "...a..Y..a....",
            "..aAa.y.aAa...",
            "..oYyYyYyYo...",
            "..oaaaaaaao...",
            "..............",
        ]),
        "snowfall-scarf": EquipmentArt(recolor: ["f": 0xE8F4FA, "F": 0x8FC3C9], at: (7, 11), overlay: [
            "w.w.",
        ]),
        "blossom-wings": EquipmentArt(at: (0, 8), overlay: [
            ".oo...",
            "oppo..",
            "opPpo.",
            ".opwpo",
            "..oppo",
            ".oppo.",
            ".oo...",
        ]),
        "sunny-sandals": EquipmentArt(shoe: .init(0xE8893A, 0xB5602A, sole: 0x6B4A2F)),
        "phoenix-wings": EquipmentArt(at: (0, 7), overlay: [
            "o.....",
            "oro...",
            "orao..",
            "oraao.",
            ".oyaao",
            ".oyhao",
            "..oyao",
            "...oo.",
        ]),
    ]
}
