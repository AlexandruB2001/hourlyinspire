import Foundation

/// How each shop item changes the walker: palette swaps (scarves, shoes, packs)
/// and/or an overlay drawn in body coordinates (hats, glasses, capes, wings).
/// Body coordinates match `CharacterSprites.upperBody`; negative `y` reaches into
/// the headroom above the head.
public struct EquipmentArt: Sendable {
    public let recolor: [Character: PixelColor]
    public let overlay: [String]
    public let x: Int
    public let y: Int

    init(recolor: [Character: UInt32] = [:], at position: (Int, Int) = (0, 0), overlay: [String] = []) {
        self.recolor = recolor.mapValues { PixelColor($0) }
        self.overlay = overlay
        x = position.0
        y = position.1
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
            "..............",
            "....oooooo....",
            "...onnnnnno...",
            "...oBBBBBBo...",
            "..onnnnnnnno..",
            ".onnnnnnnnnno.",
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
        "cherry-scarf": EquipmentArt(recolor: ["f": 0xC0583E, "F": 0x93402D]),
        "ocean-scarf": EquipmentArt(recolor: ["f": 0x4D7FB0, "F": 0x37608A]),
        "mint-scarf": EquipmentArt(recolor: ["f": 0x9BD27A, "F": 0x5FA05A]),
        "candy-scarf": EquipmentArt(recolor: ["f": 0xF4EBD0, "F": 0xC0583E], at: (7, 11), overlay: [
            "r.r.",
        ]),
        "sunset-scarf": EquipmentArt(recolor: ["f": 0xE8893A, "F": 0xB5602A]),
        "rainbow-scarf": EquipmentArt(recolor: ["F": 0x9A78D0], at: (7, 11), overlay: [
            "rayg",
        ]),
        "aurora-scarf": EquipmentArt(recolor: ["F": 0xE58AD8], at: (7, 11), overlay: [
            "gLcQ",
        ]),
        "red-sneakers": EquipmentArt(recolor: ["b": 0xC0583E, "B": 0x93402D]),
        "blue-wellies": EquipmentArt(recolor: ["b": 0x4D7FB0, "B": 0x37608A]),
        "white-sneakers": EquipmentArt(recolor: ["b": 0xF4F1E8, "B": 0xC8C4BA]),
        "moss-hikers": EquipmentArt(recolor: ["b": 0x5FA05A, "B": 0x3E7A44]),
        "cloud-walkers": EquipmentArt(recolor: ["b": 0xE8F4FA, "B": 0x8FC3C9]),
        "golden-boots": EquipmentArt(recolor: ["b": 0xE3B04B, "B": 0xB9832E]),
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
