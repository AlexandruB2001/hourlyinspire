import Foundation
import WalkscapeDomain

/// Small overlays for companion accessories, drawn with the item palette.
enum CompanionAccessoryArt {
    static let art: [String: String] = [
        "pet-bow": """
            oo.oo
            ormro
            oo.oo
            """,
        "pet-straw-hat": """
            ..ooo..
            .oyyyo.
            ooYYYoo
            oyyyyyo
            .ooooo.
            """,
        "pet-beanie": """
            ..o..
            .owo.
            orrro
            oRRRo
            """,
        "pet-flower-crown": """
            m.y.m
            ogggo
            """,
        "pet-crown": """
            o.o.o
            oyoyo
            oyyyo
            ooooo
            """,
        "pet-red-scarf": """
            orrrrro
            .oRrro.
            ...oo..
            """,
        "pet-blue-scarf": """
            ouuuuuo
            .oUuuo.
            ...oo..
            """,
        "pet-bell": """
            .......
            orrrrro
            .oyhyo.
            .oyyyo.
            ..oYo..
            """,
        "pet-backpack": """
            .ooo.
            oBnBo
            onnno
            oyyyo
            onnno
            ooooo
            """,
        "pet-pumpkin-hat": """
            ..g..
            .oao.
            oaAao
            oaaao
            """,
        "pet-snow-hat": """
            ..w..
            .oro.
            orwro
            owwwo
            """,
        "pet-petal-crown": """
            p.m.p
            opgpo
            """,
        "pet-sailor-hat": """
            .ooo.
            owwwo
            ouuuo
            """,
        "pet-star-cape": """
            ...ooo
            ..oVVo
            .oVhVo
            .oVVVo
            oVVVvo
            ohVVVo
            oo.ooo
            """,
        "pet-plus-moon-hat": """
            ..ooo
            .ouuo
            ouhuo
            ouuuo
            """,
        "pet-plus-sun-visor": """
            .ooo.
            oyyyo
            oYYYYo
            """,
        "pet-plus-leaf-cloak": """
            ...ooo
            ..oggo
            .ogLgo
            .ogggo
            ogggGo
            oLgggo
            oo.ooo
            """,
        "pet-plus-star-bow": """
            h.o.h
            hyoyh
            h.o.h
            """,
        "pet-plus-crystal-tiara": """
            c.C.c
            ocwco
            ooooo
            """,
        "pet-plus-cozy-scarf": """
            ovvvvvo
            .oVvvo.
            ...oo..
            """,
        "pet-cape": """
            ...ooo
            ..orro
            .orwro
            .orrro
            orrrRo
            owrrro
            oo.ooo
            """,
    ]

    static func sprite(_ id: String) -> Sprite? {
        art[id].map { Sprite(name: id, palette: ItemSprites.palette, art: $0) }
    }

    static func slot(of id: String) -> CompanionAccessory.Slot? {
        CompanionAccessoryCatalog.accessory(withID: id)?.slot
    }
}
