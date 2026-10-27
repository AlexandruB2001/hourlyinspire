import Foundation

/// How walking turns into coins.
public struct CoinRules: Hashable, Sendable {
    /// Earned each time today's walk passes a whole kilometre.
    public var coinsPerKilometre: Int
    /// Earned when a chest found on the walk is opened.
    public var coinsPerChest: Int
    /// Chests are hidden at random points, this many per kilometre.
    public var chestsPerKilometre: Int
    /// A new wallet starts with enough for one mystery box.
    public var starterCoins: Int

    public init(coinsPerKilometre: Int = 10, coinsPerChest: Int = 5, chestsPerKilometre: Int = 2, starterCoins: Int = 50) {
        self.coinsPerKilometre = coinsPerKilometre
        self.coinsPerChest = coinsPerChest
        self.chestsPerKilometre = max(1, chestsPerKilometre)
        self.starterCoins = starterCoins
    }

    public static let standard = CoinRules()
}

public struct WalletEvent: Hashable, Sendable {
    /// Coins from kilometre milestones in this update.
    public var coinsEarned: Int
    /// Chests reached in this update, waiting to be opened.
    public var newChests: Int

    public static let none = WalletEvent(coinsEarned: 0, newChests: 0)
}

public enum PurchaseResult: Hashable, Sendable {
    case purchased(ShopItem)
    case notEnoughCoins(needed: Int)
    case alreadyOwned
    /// A mystery box with nothing left to give.
    case soldOut
    case unknownItem
}

/// Coins, owned items and the current outfit. Like `ProgressionState`,
/// `apply(_:)` is idempotent: re-applying the same (or a lower) distance
/// never pays out twice.
public struct WalletState: Codable, Hashable, Sendable {
    public private(set) var coins: Int
    public private(set) var lifetimeCoins: Int
    public private(set) var ownedItemIDs: Set<String>
    /// Item id per `EquipmentSlot.rawValue`.
    public private(set) var equipped: [String: String]
    /// Chests reached but not yet opened. Kept across days.
    public private(set) var pendingChests: Int
    /// The local day the two counters below belong to.
    public private(set) var day: LocalDay?
    public private(set) var kilometresRewardedToday: Int
    public private(set) var chestsFoundToday: Int

    public init(rules: CoinRules = .standard) {
        coins = rules.starterCoins
        lifetimeCoins = rules.starterCoins
        ownedItemIDs = []
        equipped = [:]
        pendingChests = 0
        day = nil
        kilometresRewardedToday = 0
        chestsFoundToday = 0
    }

    // MARK: Earning

    public mutating func apply(_ progress: DailyProgress, rules: CoinRules = .standard) -> WalletEvent {
        // Delayed updates for earlier days never pay out again.
        if let day, progress.localDate < day { return .none }
        if day != progress.localDate {
            day = progress.localDate
            kilometresRewardedToday = 0
            chestsFoundToday = 0
        }
        let meters = max(0, progress.distanceMeters)
        var event = WalletEvent.none

        let kilometres = meters / 1_000
        if kilometres > kilometresRewardedToday {
            event.coinsEarned = (kilometres - kilometresRewardedToday) * rules.coinsPerKilometre
            earn(event.coinsEarned)
            kilometresRewardedToday = kilometres
        }

        let chests = Self.chestsReached(meters: meters, on: progress.localDate, rules: rules)
        if chests > chestsFoundToday {
            event.newChests = chests - chestsFoundToday
            pendingChests += event.newChests
            chestsFoundToday = chests
        }
        return event
    }

    /// Opens one waiting chest. Returns the coins it held, or nil if there were none.
    public mutating func openChest(rules: CoinRules = .standard) -> Int? {
        guard pendingChests > 0 else { return nil }
        pendingChests -= 1
        earn(rules.coinsPerChest)
        return rules.coinsPerChest
    }

    private mutating func earn(_ amount: Int) {
        coins += amount
        lifetimeCoins += amount
    }

    // MARK: Chests

    /// Where chest `index` of `day` sits. Each kilometre is split into equal
    /// segments with one chest at a random point inside each, so chests feel
    /// random but are the same however often the day is recalculated.
    public static func chestMeters(index: Int, on day: LocalDay, rules: CoinRules = .standard) -> Int {
        let segment = 1_000 / rules.chestsPerKilometre
        let margin = segment / 10
        var hash: UInt64 = 1469598103934665603
        for byte in "\(day.isoString)#\(index)".utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let span = max(1, segment - 2 * margin)
        return index * segment + margin + Int(hash % UInt64(span))
    }

    /// Number of chests reached at `meters` on `day`.
    public static func chestsReached(meters: Int, on day: LocalDay, rules: CoinRules = .standard) -> Int {
        let segment = 1_000 / rules.chestsPerKilometre
        // Every chest in a fully walked segment is reached; only the current segment needs checking.
        let full = max(0, meters) / segment
        return full + (meters >= chestMeters(index: full, on: day, rules: rules) ? 1 : 0)
    }

    // MARK: Shopping

    public func owns(_ item: ShopItem) -> Bool { ownedItemIDs.contains(item.id) }

    public mutating func buy(_ item: ShopItem) -> PurchaseResult {
        guard !owns(item) else { return .alreadyOwned }
        guard coins >= item.price else { return .notEnoughCoins(needed: item.price - coins) }
        coins -= item.price
        ownedItemIDs.insert(item.id)
        return .purchased(item)
    }

    /// Spends `ShopCatalog.mysteryBoxPrice` on a random item you don't own yet.
    /// A rarity is rolled by `Rarity.mysteryBoxWeight` (among rarities that
    /// still have unowned items), then an item of that rarity is picked evenly.
    public mutating func openMysteryBox<G: RandomNumberGenerator>(from catalog: [ShopItem] = ShopCatalog.items,
                                                                  price: Int = ShopCatalog.mysteryBoxPrice,
                                                                  using generator: inout G) -> PurchaseResult {
        let unowned = catalog.filter { !owns($0) }
        guard !unowned.isEmpty else { return .soldOut }
        guard coins >= price else { return .notEnoughCoins(needed: price - coins) }

        let rarities = Rarity.allCases.filter { rarity in unowned.contains { $0.rarity == rarity } }
        var roll = Int.random(in: 0..<rarities.reduce(0) { $0 + $1.mysteryBoxWeight }, using: &generator)
        var chosen = rarities[0]
        for rarity in rarities {
            if roll < rarity.mysteryBoxWeight {
                chosen = rarity
                break
            }
            roll -= rarity.mysteryBoxWeight
        }
        let item = unowned.filter { $0.rarity == chosen }.randomElement(using: &generator)!
        coins -= price
        ownedItemIDs.insert(item.id)
        return .purchased(item)
    }

    public mutating func openMysteryBox() -> PurchaseResult {
        var generator = SystemRandomNumberGenerator()
        return openMysteryBox(using: &generator)
    }

    // MARK: Outfit

    /// Wears `item` in its slot, replacing whatever was there. Only owned items can be worn.
    @discardableResult
    public mutating func equip(_ item: ShopItem) -> Bool {
        guard owns(item) else { return false }
        equipped[item.slot.rawValue] = item.id
        return true
    }

    public mutating func unequip(_ slot: EquipmentSlot) {
        equipped[slot.rawValue] = nil
    }

    public func isEquipped(_ item: ShopItem) -> Bool { equipped[item.slot.rawValue] == item.id }

    /// Worn item ids in slot order, for drawing the walker.
    public var outfit: [String] {
        EquipmentSlot.allCases.compactMap { equipped[$0.rawValue] }
    }
}
