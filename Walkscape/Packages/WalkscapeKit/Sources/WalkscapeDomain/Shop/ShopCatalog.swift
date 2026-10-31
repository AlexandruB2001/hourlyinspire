import Foundation

/// Where an item is worn. One item per slot.
public enum EquipmentSlot: String, Codable, Sendable, Hashable, CaseIterable {
    case head, face, neck, feet, back

    public var displayName: String {
        switch self {
        case .head: return "Hats"
        case .face: return "Glasses"
        case .neck: return "Scarves"
        case .feet: return "Shoes"
        case .back: return "Backs"
        }
    }
}

/// Rarer items are less likely to come out of the Mystery Box.
public enum Rarity: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case common, rare, epic, legendary

    public var displayName: String { rawValue.capitalized }

    /// Relative chance of a mystery box landing on this rarity (out of 100).
    public var mysteryBoxWeight: Int {
        switch self {
        case .common: return 60
        case .rare: return 28
        case .epic: return 10
        case .legendary: return 2
        }
    }

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public struct ShopItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let slot: EquipmentSlot
    public let rarity: Rarity

    public init(id: String, name: String, detail: String, slot: EquipmentSlot, rarity: Rarity) {
        self.id = id
        self.name = name
        self.detail = detail
        self.slot = slot
        self.rarity = rarity
    }

}

public enum ShopCatalog {
    /// Outfits and companion accessories only come out of the Mystery Box.
    public static let mysteryBoxPrice = 150

    /// 45 items: 18 common, 14 rare, 9 epic, 4 legendary.
    public static let items: [ShopItem] = [
        // Hats
        ShopItem(id: "straw-hat", name: "Straw Hat", detail: "Keeps the sun off on long meadow walks.", slot: .head, rarity: .common),
        ShopItem(id: "red-beanie", name: "Red Beanie", detail: "Warm, woolly and topped with a pom-pom.", slot: .head, rarity: .common),
        ShopItem(id: "bucket-hat", name: "Bucket Hat", detail: "Floppy, comfy and rain-ready.", slot: .head, rarity: .common),
        ShopItem(id: "trail-cap", name: "Trail Cap", detail: "A classic cap for serious walkers.", slot: .head, rarity: .common),
        ShopItem(id: "flower-crown", name: "Flower Crown", detail: "Woven from Sunny Meadow wildflowers.", slot: .head, rarity: .rare),
        ShopItem(id: "top-hat", name: "Top Hat", detail: "For walkers of distinction.", slot: .head, rarity: .rare),
        ShopItem(id: "explorer-helmet", name: "Explorer Helmet", detail: "Ready for any expedition.", slot: .head, rarity: .rare),
        ShopItem(id: "wizard-hat", name: "Wizard Hat", detail: "Starry, pointy and slightly magical.", slot: .head, rarity: .epic),
        ShopItem(id: "viking-helmet", name: "Viking Helmet", detail: "Horns included. Longships not.", slot: .head, rarity: .epic),
        ShopItem(id: "golden-crown", name: "Golden Crown", detail: "Ruler of the trail.", slot: .head, rarity: .legendary),
        ShopItem(id: "beret", name: "Painter's Beret", detail: "For walkers who stop to admire the view.", slot: .head, rarity: .common),
        ShopItem(id: "cat-beanie", name: "Cat-Ear Beanie", detail: "Two little ears that perk up on hills.", slot: .head, rarity: .rare),
        ShopItem(id: "frog-hat", name: "Frog Hat", detail: "Ribbit. Very waterproof.", slot: .head, rarity: .rare),
        ShopItem(id: "halo", name: "Trail Halo", detail: "A soft glow that follows the kindest walkers.", slot: .head, rarity: .legendary),
        // Glasses
        ShopItem(id: "ski-goggles", name: "Ski Goggles", detail: "Ready for the Snowy Ridge.", slot: .face, rarity: .common),
        ShopItem(id: "monocle", name: "Monocle", detail: "Most distinguished, old sport.", slot: .face, rarity: .rare),
        ShopItem(id: "star-glasses", name: "Star Glasses", detail: "Every walk is a red carpet.", slot: .face, rarity: .epic),
        ShopItem(id: "round-glasses", name: "Round Glasses", detail: "See every wildflower clearly.", slot: .face, rarity: .common),
        ShopItem(id: "sunglasses", name: "Sunglasses", detail: "Too cool for the Summit.", slot: .face, rarity: .common),
        ShopItem(id: "heart-glasses", name: "Heart Glasses", detail: "Everything looks lovely through these.", slot: .face, rarity: .rare),
        // Scarves
        ShopItem(id: "cherry-scarf", name: "Cherry Scarf", detail: "Bright red and extra cosy.", slot: .neck, rarity: .common),
        ShopItem(id: "ocean-scarf", name: "Ocean Scarf", detail: "The colour of Lakeside on a clear day.", slot: .neck, rarity: .common),
        ShopItem(id: "mint-scarf", name: "Mint Scarf", detail: "Fresh as a spring morning.", slot: .neck, rarity: .common),
        ShopItem(id: "candy-scarf", name: "Candy Stripe Scarf", detail: "Red and white, like a sweet shop.", slot: .neck, rarity: .rare),
        ShopItem(id: "sunset-scarf", name: "Sunset Scarf", detail: "Dyed the orange of a canyon evening.", slot: .neck, rarity: .rare),
        ShopItem(id: "rainbow-scarf", name: "Rainbow Scarf", detail: "Every colour of the journey.", slot: .neck, rarity: .epic),
        ShopItem(id: "bandana", name: "Trail Bandana", detail: "A red bandana for dusty canyon paths.", slot: .neck, rarity: .common),
        ShopItem(id: "bow-tie", name: "Blue Bow Tie", detail: "Smart enough for the Hearth Village.", slot: .neck, rarity: .common),
        ShopItem(id: "flower-lei", name: "Flower Lei", detail: "Picked fresh in the Blossom Orchard.", slot: .neck, rarity: .rare),
        ShopItem(id: "aurora-scarf", name: "Aurora Scarf", detail: "Spun from the lights over Starlight Pass.", slot: .neck, rarity: .legendary),
        // Shoes
        ShopItem(id: "red-sneakers", name: "Red Sneakers", detail: "Speedy-looking, at least.", slot: .feet, rarity: .common),
        ShopItem(id: "blue-wellies", name: "Blue Wellies", detail: "Puddles fear you now.", slot: .feet, rarity: .common),
        ShopItem(id: "white-sneakers", name: "White Sneakers", detail: "Fresh out of the box.", slot: .feet, rarity: .common),
        ShopItem(id: "moss-hikers", name: "Moss Hikers", detail: "Grippy boots for forest trails.", slot: .feet, rarity: .rare),
        ShopItem(id: "cloud-walkers", name: "Cloud Walkers", detail: "Like walking on the Cloud Forest mist.", slot: .feet, rarity: .rare),
        ShopItem(id: "yellow-wellies", name: "Yellow Wellies", detail: "Made for jumping in puddles.", slot: .feet, rarity: .common),
        ShopItem(id: "roller-skates", name: "Roller Skates", detail: "Strictly for the flat bits.", slot: .feet, rarity: .epic),
        ShopItem(id: "golden-boots", name: "Golden Boots", detail: "Every step shines.", slot: .feet, rarity: .epic),
        // Backs
        ShopItem(id: "explorer-pack", name: "Explorer Pack", detail: "A blue pack with a golden bedroll.", slot: .back, rarity: .rare),
        ShopItem(id: "bindle", name: "Bindle", detail: "Everything you need, tied up in a cloth.", slot: .back, rarity: .common),
        ShopItem(id: "turtle-shell", name: "Turtle Shell", detail: "Slow and steady wins the walk.", slot: .back, rarity: .rare),
        ShopItem(id: "guitar", name: "Trail Guitar", detail: "For campfire songs at the end of the day.", slot: .back, rarity: .epic),
        ShopItem(id: "hero-cape", name: "Hero Cape", detail: "Flaps dramatically in the wind.", slot: .back, rarity: .epic),
        ShopItem(id: "fairy-wings", name: "Fairy Wings", detail: "Glassy wings that catch the light.", slot: .back, rarity: .epic),
        ShopItem(id: "phoenix-wings", name: "Phoenix Wings", detail: "Fiery wings for the most dedicated walkers.", slot: .back, rarity: .legendary),
    ]

    /// Coin-shop items and premium outfit pieces (which are never sold for coins).
    public static func item(withID id: String) -> ShopItem? {
        items.first { $0.id == id } ?? PremiumOutfits.items.first { $0.id == id }
    }
}

/// Something the Mystery Box can give: a walker outfit piece or a companion accessory.
public enum MysteryBoxPrize: Identifiable, Hashable, Sendable {
    case outfit(ShopItem)
    case accessory(CompanionAccessory, rarity: Rarity)

    public var id: String {
        switch self {
        case .outfit(let item): return item.id
        case .accessory(let accessory, _): return accessory.id
        }
    }

    public var name: String {
        switch self {
        case .outfit(let item): return item.name
        case .accessory(let accessory, _): return accessory.name
        }
    }

    public var rarity: Rarity {
        switch self {
        case .outfit(let item): return item.rarity
        case .accessory(_, let rarity): return rarity
        }
    }
}

public enum MysteryBox {
    /// Everything the box can give on `day`. Festival accessories join once
    /// their festival is over; level gifts and Plus gifts never do.
    public static func prizes(on day: LocalDay) -> [MysteryBoxPrize] {
        ShopCatalog.items.map(MysteryBoxPrize.outfit)
            + CompanionAccessoryCatalog.all.compactMap { accessory in
                guard accessory.isInMysteryBox(on: day), let rarity = accessory.rarity else { return nil }
                return .accessory(accessory, rarity: rarity)
            }
    }
}
