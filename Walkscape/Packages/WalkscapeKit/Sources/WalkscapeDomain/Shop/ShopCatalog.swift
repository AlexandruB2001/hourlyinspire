import Foundation

/// Where an item is worn. One item per slot.
public enum EquipmentSlot: String, Codable, Sendable, Hashable, CaseIterable {
    /// Tops come first: they recolour the tunic, and scarves (neck) recolour over a hoodie's collar.
    /// Trails aren't drawn on the walker but behind it (see `Contrails`).
    case top, head, face, neck, feet, back, trail

    public var displayName: String {
        switch self {
        case .top: return "Tops"
        case .head: return "Hats"
        case .face: return "Glasses"
        case .neck: return "Scarves"
        case .feet: return "Shoes"
        case .back: return "Backs"
        case .trail: return "Trails"
        }
    }
}

/// Rarer items are less likely to come out of the Mystery Box.
public enum Rarity: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case common, rare, epic, legendary

    public var displayName: String { rawValue.capitalized }

    /// Relative chance of a mystery box landing on this rarity (out of 100).
    /// Coins back when the Mystery Box gives an item you already own. The box
    /// rolls from everything, so these keep a duplicate from feeling wasted.
    public var duplicateRefund: Int {
        switch self {
        case .common: return 80
        case .rare: return 100
        case .epic: return 150
        case .legendary: return 200
        }
    }

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

    /// 62 items: 23 common, 20 rare, 11 epic, 8 legendary.
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
        // Tops
        ShopItem(id: "white-tee", name: "White Tee", detail: "A crisp white tee for sunny strolls.", slot: .top, rarity: .common),
        ShopItem(id: "red-tee", name: "Red Tee", detail: "Bright red, easy to spot on the trail.", slot: .top, rarity: .common),
        ShopItem(id: "blue-tee", name: "Blue Tee", detail: "Sky blue and soft as a cloud.", slot: .top, rarity: .common),
        ShopItem(id: "yellow-tee", name: "Sunny Tee", detail: "A cheerful yellow tee.", slot: .top, rarity: .common),
        ShopItem(id: "pink-tee", name: "Blossom Tee", detail: "Soft pink, like orchard blossom.", slot: .top, rarity: .common),
        ShopItem(id: "cream-knit-sweater", name: "Cream Knit Sweater", detail: "Chunky cream knit with little berry dots.", slot: .top, rarity: .rare),
        ShopItem(id: "forest-sweater", name: "Forest Sweater", detail: "Pine green with a cream stripe.", slot: .top, rarity: .rare),
        ShopItem(id: "berry-sweater", name: "Berry Sweater", detail: "Purple knit with a pink band.", slot: .top, rarity: .rare),
        ShopItem(id: "sailor-sweater", name: "Sailor Sweater", detail: "Navy and cream stripes for seaside walks.", slot: .top, rarity: .rare),
        ShopItem(id: "grey-hoodie", name: "Cosy Grey Hoodie", detail: "The comfiest hoodie, hood and all.", slot: .top, rarity: .rare),
        ShopItem(id: "sunset-hoodie", name: "Sunset Hoodie", detail: "Warm orange, like the end of a long walk.", slot: .top, rarity: .rare),
        ShopItem(id: "lavender-hoodie", name: "Lavender Hoodie", detail: "Soft lavender from the fields past the orchard.", slot: .top, rarity: .epic),
        ShopItem(id: "starry-hoodie", name: "Starry Night Hoodie", detail: "Midnight blue, scattered with tiny stars.", slot: .top, rarity: .epic),
        // Trails: all legendary, the rarest pulls in the box.
        ShopItem(id: "rainbow-contrail", name: "Rainbow Contrail", detail: "A ribbon of every colour streams behind you.", slot: .trail, rarity: .legendary),
        ShopItem(id: "comet-contrail", name: "Comet Trail", detail: "Sparks and embers, like a shooting star.", slot: .trail, rarity: .legendary),
        ShopItem(id: "stardust-contrail", name: "Stardust Trail", detail: "Twinkling dust from Starlight Pass.", slot: .trail, rarity: .legendary),
        ShopItem(id: "bubble-contrail", name: "Bubble Trail", detail: "Shimmering bubbles float up from every step.", slot: .trail, rarity: .legendary),
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
    /// Any prize by id, whatever the day (the server picks which).
    public static func prize(withID id: String) -> MysteryBoxPrize? {
        if let item = ShopCatalog.items.first(where: { $0.id == id }) { return .outfit(item) }
        if let accessory = CompanionAccessoryCatalog.all.first(where: { $0.id == id }), let rarity = accessory.rarity {
            return .accessory(accessory, rarity: rarity)
        }
        return nil
    }

    public static func prizes(on day: LocalDay) -> [MysteryBoxPrize] {
        ShopCatalog.items.map(MysteryBoxPrize.outfit)
            + CompanionAccessoryCatalog.all.compactMap { accessory in
                guard accessory.isInMysteryBox(on: day), let rarity = accessory.rarity else { return nil }
                return .accessory(accessory, rarity: rarity)
            }
    }
}

/// What each trail item (`EquipmentSlot.trail`) draws behind the walker.
public enum Contrails {
    public static let effects: [String: TrailEffect] = [
        "rainbow-contrail": TrailEffect(id: "rainbow-contrail", name: "Rainbow Contrail",
                                        colors: [0xE8574A, 0xF2A33A, 0xF4D35E, 0x7DBA5E, 0x5AA9E6, 0x9B7BD8], style: .ribbon),
        "comet-contrail": TrailEffect(id: "comet-contrail", name: "Comet Trail",
                                      colors: [0xFFF3B0, 0xFFC94A, 0xF27A2E, 0xC7402D], style: .embers),
        "stardust-contrail": TrailEffect(id: "stardust-contrail", name: "Stardust Trail",
                                         colors: [0xFFFFFF, 0xB49AE0, 0x7FE0E8, 0xFFE59A], style: .stardust),
        "bubble-contrail": TrailEffect(id: "bubble-contrail", name: "Bubble Trail",
                                       colors: [0xBFE6F2, 0xFFFFFF, 0xF4B6C8], style: .bubbles),
    ]

    public static func effect(forItemID id: String?) -> TrailEffect? { id.flatMap { effects[$0] } }
}

/// The free chest in the Shop: one a day, back at the player's midnight. The
/// server rolls the coins and works out the day from its own clock, so
/// changing the phone's clock or reinstalling can't open it early or change
/// what's inside. How much it holds is a surprise.
public enum DailyChest {
    /// What it can hold, and how often (weights out of 100): bigger amounts are rarer.
    public static let odds: [(coins: Int, weight: Int)] = [(25, 30), (30, 22), (40, 15), (50, 10), (60, 8), (75, 6), (100, 4), (125, 3), (150, 2)]
    public static var range: ClosedRange<Int> { odds.map(\.coins).min()!...odds.map(\.coins).max()! }

    /// The wallet key a claim is paid under. The server writes the same key,
    /// and replaces every key with this prefix from its own records.
    public static func earnedKey(claimID: String) -> String { "daily-chest-\(claimID)" }

    /// The next midnight after `date` in `timeZone` (when demo walking's chest is back).
    public static func nextReset(after date: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                 matchingPolicy: .nextTime) ?? date.addingTimeInterval(24 * 60 * 60)
    }

    /// A roll for demo walking (the server rolls for Apple Health players).
    public static func roll<G: RandomNumberGenerator>(using generator: inout G) -> Int {
        var roll = Int.random(in: 0..<odds.reduce(0) { $0 + $1.weight }, using: &generator)
        for entry in odds {
            if roll < entry.weight { return entry.coins }
            roll -= entry.weight
        }
        return odds[0].coins
    }
}
