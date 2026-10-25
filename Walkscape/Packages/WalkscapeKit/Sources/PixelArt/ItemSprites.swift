import Foundation

/// 10x10 icons for collectibles and achievements.
public enum ItemSprites {
    static let palette = SpritePalette([
        "o": PixelColor(0x1E2233),
        "g": PixelColor(0x5FA05A), "G": PixelColor(0x3E7A44), "L": PixelColor(0x9BD27A),
        "s": PixelColor(0x9AA4B0), "S": PixelColor(0x6E7884), "W": PixelColor(0xD5DCE3),
        "b": PixelColor(0x9A6A3E), "B": PixelColor(0x6B4A2F), "n": PixelColor(0xC48A4E),
        "y": PixelColor(0xE3B04B), "Y": PixelColor(0xB9832E), "h": PixelColor(0xFFE59A),
        "w": PixelColor(0xFFF6E0), "p": PixelColor(0xF2B7A8), "P": PixelColor(0xD98A7A),
        "c": PixelColor(0x7FE0E8), "C": PixelColor(0x3FA8C0), "m": PixelColor(0xE58AD8),
        "r": PixelColor(0xC0583E), "R": PixelColor(0x93402D), "u": PixelColor(0x4D7FB0), "U": PixelColor(0x37608A),
        "k": PixelColor(0x8FC3C9),
    ])

    static let art: [String: String] = [
        "clover": """
            ...oo.oo..
            ..oLgogLo.
            ..ogggggo.
            ...oggoo..
            .ooggggoo.
            oLgggoggLo
            oggGoogggo
            .oooboooo.
            ....bo....
            ....oo....
            """,
        "stone": """
            ..........
            ...oooo...
            ..oWWsso..
            .oWsssSSo.
            .osssssSo.
            .ossssSSo.
            ..oSSSSo..
            ...oooo...
            ..........
            ..........
            """,
        "pinecone": """
            ....oo....
            ...oGGo...
            ..ohnnho..
            ..onBnBo..
            .ohnnnnho.
            .onBnBnBo.
            .onnnnnno.
            ..onBnBo..
            ...onno...
            ....oo....
            """,
        "feather": """
            .......oo.
            ......owwo
            .....owwko
            ....owwko.
            ...owwko..
            ..owwko...
            .owwko....
            .okko.....
            .oo.......
            o.........
            """,
        "shell": """
            ..........
            ...oooo...
            ..opppPo..
            .opwppPPo.
            .opppwpPo.
            .oPpppPPo.
            ..oPPPPo..
            ...oPPo...
            ....oo....
            ..........
            """,
        "lantern": """
            ...oooo...
            ...o..o...
            ..oYYYYo..
            ..ohhyho..
            ..ohwyho..
            ..ohhyho..
            ..oyhhyo..
            ..oYYYYo..
            ...oooo...
            ..........
            """,
        "crystal": """
            ....oo....
            ...owco...
            ...owco...
            ..owccCo..
            ..owccCo..
            .omwccCCo.
            .ommccCCo.
            ..omcCCo..
            ...oooo...
            ..........
            """,
        "snowflake": """
            ....oo....
            .o.owwo.o.
            .owowwowo.
            ..owkkwo..
            oowkwwkwoo
            oowkwwkwoo
            ..owkkwo..
            .owowwowo.
            .o.owwo.o.
            ....oo....
            """,
        "mushroom": """
            ...oooo...
            ..occmco..
            .occccmco.
            .omcccccmo
            .oooooooo.
            ...owwo...
            ...owwo...
            ...owwo...
            ...oooo...
            ..........
            """,
        "flag": """
            .oooooo...
            .orrrrro..
            .orrRrrro.
            .orrrrro..
            .ooooooo..
            .ob.......
            .ob.......
            .ob.......
            oobo......
            ooooo.....
            """,
        "boot": """
            ..........
            ..ooooo...
            ..obbbo...
            ..obbbo...
            ..obnbo...
            ..obbbooo.
            .obbbbbbo.
            .oBBBBBBo.
            .oooooooo.
            ..........
            """,
        "star": """
            ....oo....
            ....oyo...
            ...oyyo...
            ooooyhyooo
            oyyyhhyyyo
            .oyyhyyyo.
            ..oyyyyo..
            .oyyooyyo.
            .oyo..oyo.
            .oo....oo.
            """,
        "compass": """
            ...oooo...
            ..oyyyyo..
            .oywwwwyo.
            oywwrwwwyo
            oywwrrwwyo
            oywwuuwwyo
            oywwwuwwyo
            .oywwwwyo.
            ..oyyyyo..
            ...oooo...
            """,
        "medal": """
            .ouo..oro.
            .oUuoorRo.
            ..oUuorRo.
            ...ooooo..
            ...oyyyo..
            ..oyhyyYo.
            ..oyyyyYo.
            ..oyyyYYo.
            ...oYYYo..
            ....ooo...
            """,
        "pouch": """
            ....oo....
            ...obbo...
            ..ooyyoo..
            .obnbbnbo.
            obnbbbbnbo
            obbbbbbbbo
            obbbbbbbBo
            .oBbbbbBo.
            ..oooooo..
            ..........
            """,
        "map": """
            ..........
            oooooooooo
            owwwowwwwo
            owrwowwuwo
            owwwrwwuuo
            owwwowrwwo
            owuuowwrwo
            owwwowwwwo
            oooooooooo
            ..........
            """,
    ]

    public static let allIDs: [String] = art.keys.sorted()

    public static func sprite(_ id: String) -> Sprite? {
        art[id].map { Sprite(name: id, palette: palette, art: $0) }
    }

    public static func render(_ id: String) -> PixelCanvas {
        sprite(id)?.render() ?? PixelCanvas(width: 10, height: 10)
    }
}
