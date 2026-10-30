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
            ooo
            oyo
            .o.
            """,
        "pet-backpack": """
            ooo
            onn
            onn
            ooo
            """,
        "pet-cape": """
            oo.
            orr
            orr
            orR
            ooo
            """,
    ]

    static func sprite(_ id: String) -> Sprite? {
        art[id].map { Sprite(name: id, palette: ItemSprites.palette, art: $0) }
    }

    static func slot(of id: String) -> CompanionAccessory.Slot? {
        CompanionAccessoryCatalog.accessory(withID: id)?.slot
    }
}
