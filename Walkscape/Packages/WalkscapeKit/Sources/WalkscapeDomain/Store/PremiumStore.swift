import Foundation

// MARK: - Products

/// Something sold for real money through the App Store. Everything here is
/// cosmetic: no coins, XP, progress or features are ever sold.
public struct StoreProduct: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case subscription, bundle
    }

    /// The App Store product id.
    public let id: String
    public let kind: Kind
    public let name: String
    public let summary: String
    /// Shown until the App Store's localized price loads.
    public let fallbackPrice: String
    /// Cosmetic ids a bundle unlocks forever (outfit items, skins, trails, decorations).
    public let contents: [String]

    public init(id: String, kind: Kind, name: String, summary: String, fallbackPrice: String, contents: [String] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.fallbackPrice = fallbackPrice
        self.contents = contents
    }
}

public enum StoreCatalog {
    public static let prefix = "com.alexandrub.walkscape."
    public static let plusMonthlyID = prefix + "plus.monthly"
    public static let plusYearlyID = prefix + "plus.yearly"
    /// The App Store subscription group both Plus plans belong to.
    public static let plusGroupName = "Walkscape Plus"

    public static let plus: [StoreProduct] = [
        StoreProduct(id: plusMonthlyID, kind: .subscription, name: "Walkscape Plus (monthly)",
                     summary: "All Plus cosmetics, renewed every month.", fallbackPrice: "$2.99"),
        StoreProduct(id: plusYearlyID, kind: .subscription, name: "Walkscape Plus (yearly)",
                     summary: "All Plus cosmetics for a year. Save about 44%.", fallbackPrice: "$19.99"),
    ]

    public static let bundles: [StoreProduct] = [
        StoreProduct(id: prefix + "bundle.seasonal-outfits", kind: .bundle, name: "Seasonal Outfit Bundle",
                     summary: "Four outfit pieces, one for every season.", fallbackPrice: "$2.99",
                     contents: PremiumOutfits.items.map(\.id)),
        StoreProduct(id: prefix + "bundle.companion-skins", kind: .bundle, name: "Companion Skins",
                     summary: "Golden, Frost and Shadow looks for any companion.", fallbackPrice: "$1.99",
                     contents: CompanionSkinCatalog.all.map(\.id)),
        StoreProduct(id: prefix + "bundle.trail-sparkles", kind: .bundle, name: "Trail Sparkles",
                     summary: "Sparkles, petals or stars behind you as you walk.", fallbackPrice: "$0.99",
                     contents: TrailEffectCatalog.all.map(\.id)),
        StoreProduct(id: prefix + "bundle.campsite-decor", kind: .bundle, name: "Cozy Campsite Decor",
                     summary: "A hammock, string lights and a cocoa stand for your team's camp.", fallbackPrice: "$1.99",
                     contents: CampfireCatalog.premiumDecorations.map(\.id)),
    ]

    public static var all: [StoreProduct] { plus + bundles }
    public static var allIDs: [String] { all.map(\.id) }

    public static func product(withID id: String) -> StoreProduct? { all.first { $0.id == id } }

    /// What Plus includes, for the store screen.
    public static let plusPerks = [
        "A new exclusive companion accessory every month you're a member, yours to keep",
        "Premium profile frames: Prism, Starlight and Ember",
        "Journal themes: Moonlight, Meadow and Parchment",
        "Two extra campsite decorations for your team",
        "Festival accessories unlocked from the very first tier",
    ]
}

// MARK: - Entitlements

/// What the player owns from the store. Built from verified App Store
/// transactions (on the phone, and recorded on the server).
public struct Entitlements: Codable, Hashable, Sendable {
    /// Bundle product ids owned forever.
    public var bundles: Set<String>
    /// When the Plus subscription runs out (nil: not subscribed).
    public var plusExpires: Date?

    public init(bundles: Set<String> = [], plusExpires: Date? = nil) {
        self.bundles = bundles
        self.plusExpires = plusExpires
    }

    public func hasPlus(at now: Date) -> Bool { plusExpires.map { $0 > now } ?? false }

    /// Every cosmetic id owned through bundles.
    public var bundleCosmetics: Set<String> {
        Set(StoreCatalog.bundles.filter { bundles.contains($0.id) }.flatMap(\.contents))
    }

    public func owns(_ cosmeticID: String) -> Bool { bundleCosmetics.contains(cosmeticID) }
}

// MARK: - Plus monthly gift

public enum PlusMonthlyGift {
    /// The companion accessory gifted in each month, cycling through the list.
    public static let rotation = ["pet-plus-moon-hat", "pet-plus-sun-visor", "pet-plus-leaf-cloak",
                                  "pet-plus-star-bow", "pet-plus-crystal-tiara", "pet-plus-cozy-scarf"]

    public static func itemID(for day: LocalDay) -> String {
        rotation[((day.year * 12 + day.month) % rotation.count + rotation.count) % rotation.count]
    }

    /// Claimed once per month of membership; the item stays after Plus ends.
    public static func reward(for day: LocalDay) -> Reward {
        Reward(id: String(format: "plus-gift-%04d-%02d", day.year, day.month), itemIDs: [itemID(for: day)])
    }
}

// MARK: - Premium cosmetics

/// Walker outfit pieces from the Seasonal Outfit Bundle. They wear like shop
/// items but are never in the coin shop or the Mystery Box.
public enum PremiumOutfits {
    public static let items: [ShopItem] = [
        ShopItem(id: "harvest-crown", name: "Harvest Crown", detail: "Woven wheat and maple leaves.", slot: .head, rarity: .epic),
        ShopItem(id: "snowfall-scarf", name: "Snowfall Scarf", detail: "Knitted with tiny snowflakes.", slot: .neck, rarity: .epic),
        ShopItem(id: "blossom-wings", name: "Blossom Wings", detail: "Petal wings that never wilt.", slot: .back, rarity: .epic),
        ShopItem(id: "sunny-sandals", name: "Sunny Sandals", detail: "For long summer evenings.", slot: .feet, rarity: .epic),
    ]
}

public struct CompanionSkin: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Main colours as 0xRRGGBB: body, shade, accent.
    public let colors: [UInt32]
}

public enum CompanionSkinCatalog {
    public static let all: [CompanionSkin] = [
        CompanionSkin(id: "skin-golden", name: "Golden", colors: [0xE3B04B, 0xB9832E, 0xFFE59A]),
        CompanionSkin(id: "skin-frost", name: "Frost", colors: [0xBFE6F2, 0x7FB8D0, 0xFFFFFF]),
        CompanionSkin(id: "skin-shadow", name: "Shadow", colors: [0x4B4466, 0x2E2A40, 0xB49AE0]),
    ]

    public static func skin(withID id: String?) -> CompanionSkin? { all.first { $0.id == id } }
}

public struct TrailEffect: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Particle colours as 0xRRGGBB.
    public let colors: [UInt32]
}

public enum TrailEffectCatalog {
    public static let all: [TrailEffect] = [
        TrailEffect(id: "trail-sparkles", name: "Sparkles", colors: [0xFFE59A, 0xFFFFFF]),
        TrailEffect(id: "trail-petals", name: "Petals", colors: [0xF4B6C8, 0xFFF3F6]),
        TrailEffect(id: "trail-stars", name: "Stardust", colors: [0xB49AE0, 0x7FE0E8, 0xFFFFFF]),
    ]

    public static func effect(withID id: String?) -> TrailEffect? { all.first { $0.id == id } }
}

/// A Journal colour theme (Plus).
public struct JournalTheme: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Panel fill and accent as 0xRRGGBB.
    public let fill: UInt32
    public let accent: UInt32
}

public enum JournalThemeCatalog {
    public static let defaultID = "classic"
    public static let all: [JournalTheme] = [
        JournalTheme(id: "classic", name: "Classic", fill: 0x24413A, accent: 0xE3B04B),
        JournalTheme(id: "moonlight", name: "Moonlight", fill: 0x232A4A, accent: 0xB49AE0),
        JournalTheme(id: "meadow", name: "Meadow", fill: 0x2F5A3E, accent: 0xF4B6C8),
        JournalTheme(id: "parchment", name: "Parchment", fill: 0x5B4632, accent: 0xFFE59A),
    ]

    public static func theme(withID id: String?) -> JournalTheme { all.first { $0.id == id } ?? all[0] }
    public static func isPlus(_ id: String) -> Bool { id != defaultID }
}

/// The player's chosen premium looks (only applied while owned).
public struct PremiumLook: Codable, Hashable, Sendable {
    public var companionSkinID: String?
    public var trailEffectID: String?
    public var journalThemeID: String

    public init(companionSkinID: String? = nil, trailEffectID: String? = nil, journalThemeID: String = JournalThemeCatalog.defaultID) {
        self.companionSkinID = companionSkinID
        self.trailEffectID = trailEffectID
        self.journalThemeID = journalThemeID
    }

    /// Drops anything no longer owned (e.g. a lapsed Plus subscription).
    public func validated(entitlements: Entitlements, now: Date) -> PremiumLook {
        var look = self
        if let skin = companionSkinID, !entitlements.owns(skin) { look.companionSkinID = nil }
        if let trail = trailEffectID, !entitlements.owns(trail) { look.trailEffectID = nil }
        if JournalThemeCatalog.isPlus(journalThemeID) && !entitlements.hasPlus(at: now) {
            look.journalThemeID = JournalThemeCatalog.defaultID
        }
        return look
    }
}
