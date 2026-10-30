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

/// A chest earned when someone you invited starts walking. Its coin amount
/// is decided by the server (25-100) when the referral qualifies.
public struct ReferralChest: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let coins: Int

    public init(id: String, coins: Int) {
        self.id = id
        self.coins = coins
    }
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
///
/// Every coin earned or spent is kept under a stable key (a day's walking,
/// a reward id, an item bought, one ad view...). Merging two phones takes the
/// larger amount per key, so an earning or purchase seen on both counts once
/// and nothing from either phone is lost or doubled.
public struct WalletState: Codable, Hashable, Sendable {
    /// Coins earned, by source key.
    public private(set) var earned: [String: Int]
    /// Coins spent, by purchase key.
    public private(set) var spent: [String: Int]
    public private(set) var ownedItemIDs: Set<String>
    /// Item id per `EquipmentSlot.rawValue`.
    public private(set) var equipped: [String: String]
    /// Chests found and opened, by the day they were found ("legacy" for older saves).
    public private(set) var chestsFound: [String: Int]
    public private(set) var chestsOpened: [String: Int]
    /// The local day the two counters below belong to.
    public private(set) var day: LocalDay?
    public private(set) var kilometresRewardedToday: Int
    public private(set) var chestsFoundToday: Int
    /// Referral chests waiting to be opened.
    public private(set) var referralChests: [ReferralChest]
    /// Referral chests already opened; a chest id is only ever paid once.
    public private(set) var openedReferralChestIDs: Set<String>

    static let legacyKey = "legacy"
    static let starterKey = "starter"

    public init(rules: CoinRules = .standard) {
        earned = [Self.starterKey: rules.starterCoins]
        spent = [:]
        ownedItemIDs = []
        equipped = [:]
        chestsFound = [:]
        chestsOpened = [:]
        day = nil
        kilometresRewardedToday = 0
        chestsFoundToday = 0
        referralChests = []
        openedReferralChestIDs = []
    }

    public var lifetimeCoins: Int { earned.values.reduce(0, +) }
    /// Coins spent so far.
    public var spentCoins: Int { spent.values.reduce(0, +) }
    public var coins: Int { max(0, lifetimeCoins - spentCoins) }
    /// Chests reached but not yet opened. Kept across days.
    public var pendingChests: Int {
        chestsFound.reduce(0) { $0 + max(0, $1.value - (chestsOpened[$1.key] ?? 0)) }
    }

    enum CodingKeys: String, CodingKey {
        case earned, spent, chestsFound, chestsOpened
        case ownedItemIDs, equipped, day, kilometresRewardedToday, chestsFoundToday
        case referralChests, openedReferralChestIDs
        // Totals, and the only fields in older saves.
        case coins, lifetimeCoins, pendingChests
    }

    /// Saves from before keyed coins move their totals into a "legacy" entry.
    /// An app update never changes anyone's coins, chests or items.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownedItemIDs = try container.decode(Set<String>.self, forKey: .ownedItemIDs)
        equipped = try container.decode([String: String].self, forKey: .equipped)
        day = try container.decodeIfPresent(LocalDay.self, forKey: .day)
        kilometresRewardedToday = try container.decode(Int.self, forKey: .kilometresRewardedToday)
        chestsFoundToday = try container.decode(Int.self, forKey: .chestsFoundToday)
        referralChests = try container.decodeIfPresent([ReferralChest].self, forKey: .referralChests) ?? []
        openedReferralChestIDs = try container.decodeIfPresent(Set<String>.self, forKey: .openedReferralChestIDs) ?? []
        if let earned = try container.decodeIfPresent([String: Int].self, forKey: .earned) {
            self.earned = earned
            spent = try container.decodeIfPresent([String: Int].self, forKey: .spent) ?? [:]
            chestsFound = try container.decodeIfPresent([String: Int].self, forKey: .chestsFound) ?? [:]
            chestsOpened = try container.decodeIfPresent([String: Int].self, forKey: .chestsOpened) ?? [:]
            return
        }
        let coins = try container.decode(Int.self, forKey: .coins)
        let lifetime = try container.decode(Int.self, forKey: .lifetimeCoins)
        let pending = try container.decode(Int.self, forKey: .pendingChests)
        // The starter coins keep their key, so a new phone's starter coins aren't added again.
        let starter = min(lifetime, CoinRules.standard.starterCoins)
        earned = [Self.starterKey: starter, Self.legacyKey: lifetime - starter]
        spent = [Self.legacyKey: max(0, lifetime - coins)]
        chestsFound = pending > 0 ? [Self.legacyKey: pending] : [:]
        chestsOpened = [:]
        if let day {
            // Today's walking is already inside the legacy total. It gets its
            // own key (so later kilometres today add on top) with a matching
            // offset, so two older saves never count the same day twice.
            let walk = kilometresRewardedToday * CoinRules.standard.coinsPerKilometre
            earned[Self.walkKey(day)] = walk
            spent["legacy-\(Self.walkKey(day))"] = walk
            // Today's chests so far are counted as handled; any still waiting are in the legacy pile.
            chestsFound[day.isoString] = chestsFoundToday
            chestsOpened[day.isoString] = chestsFoundToday
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(earned, forKey: .earned)
        try container.encode(spent, forKey: .spent)
        try container.encode(chestsFound, forKey: .chestsFound)
        try container.encode(chestsOpened, forKey: .chestsOpened)
        try container.encode(ownedItemIDs, forKey: .ownedItemIDs)
        try container.encode(equipped, forKey: .equipped)
        try container.encodeIfPresent(day, forKey: .day)
        try container.encode(kilometresRewardedToday, forKey: .kilometresRewardedToday)
        try container.encode(chestsFoundToday, forKey: .chestsFoundToday)
        try container.encode(referralChests, forKey: .referralChests)
        try container.encode(openedReferralChestIDs, forKey: .openedReferralChestIDs)
        try container.encode(coins, forKey: .coins)
        try container.encode(lifetimeCoins, forKey: .lifetimeCoins)
        try container.encode(pendingChests, forKey: .pendingChests)
    }

    static func walkKey(_ day: LocalDay) -> String { "walk-\(day.isoString)" }
    static func chestKey(_ found: String) -> String { "chests-\(found)" }

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
            kilometresRewardedToday = kilometres
            let key = Self.walkKey(progress.localDate)
            earned[key] = max(earned[key] ?? 0, kilometres * rules.coinsPerKilometre)
        }

        let chests = Self.chestsReached(meters: meters, on: progress.localDate, rules: rules)
        if chests > chestsFoundToday {
            event.newChests = chests - chestsFoundToday
            chestsFoundToday = chests
            let key = progress.localDate.isoString
            chestsFound[key] = max(chestsFound[key] ?? 0, chests)
        }
        return event
    }

    // MARK: Opening chests

    /// Every chest has a permanent id: the day it was found and its number that
    /// day ("2026-10-27#3"; "legacy#0" for chests waiting in older saves).
    /// Chests of a day open in order, so the opened count says which are opened.
    public static func chestID(day key: String, index: Int) -> String { "\(key)#\(index)" }

    /// Waiting chests, oldest first.
    public var pendingChestIDs: [String] {
        chestsFound.keys.sorted().flatMap { key in
            ((chestsOpened[key] ?? 0)..<max(chestsOpened[key] ?? 0, chestsFound[key] ?? 0)).map { Self.chestID(day: key, index: $0) }
        }
    }

    public func isChestOpened(_ id: String) -> Bool {
        guard let chest = Self.parseChestID(id) else { return false }
        return chest.index < (chestsOpened[chest.day] ?? 0)
    }

    /// Opens one waiting chest (the oldest first). Returns the coins it held, or nil if there were none.
    public mutating func openChest(rules: CoinRules = .standard) -> Int? {
        guard let id = pendingChestIDs.first else { return nil }
        return openChest(id: id, rules: rules)
    }

    /// Opens the chest with `id`. Opening it again, or a chest that was never
    /// found, pays nothing, so a repeated tap or retry can't pay twice.
    @discardableResult
    public mutating func openChest(id: String, rules: CoinRules = .standard) -> Int? {
        guard let chest = Self.parseChestID(id), chest.index == (chestsOpened[chest.day] ?? 0),
              chest.index < (chestsFound[chest.day] ?? 0) else { return nil }
        chestsOpened[chest.day] = chest.index + 1
        earned[Self.chestKey(chest.day)] = (chest.index + 1) * rules.coinsPerChest
        return rules.coinsPerChest
    }

    static func parseChestID(_ id: String) -> (day: String, index: Int)? {
        guard let hash = id.lastIndex(of: "#"), let index = Int(id[id.index(after: hash)...]) else { return nil }
        return (String(id[..<hash]), index)
    }

    /// Adds chests the server says are ready. Chests already waiting or
    /// opened are ignored, so this can be called on every refresh.
    @discardableResult
    public mutating func receiveReferralChests(_ chests: [ReferralChest]) -> [ReferralChest] {
        var added: [ReferralChest] = []
        for chest in chests where !openedReferralChestIDs.contains(chest.id) && !referralChests.contains(where: { $0.id == chest.id }) {
            referralChests.append(chest)
            added.append(chest)
        }
        return added
    }

    /// Opens a referral chest. Returns its coins, or nil if it isn't waiting.
    public mutating func openReferralChest(id: String) -> Int? {
        guard let index = referralChests.firstIndex(where: { $0.id == id }) else { return nil }
        let chest = referralChests.remove(at: index)
        openedReferralChestIDs.insert(chest.id)
        earned["referral-\(chest.id)"] = chest.coins
        return chest.coins
    }

    /// Pays a `Reward` (see `RewardLedger.claim`, which makes sure it happens once).
    public mutating func receiveReward(id: String, coins: Int, itemIDs: [String]) {
        if coins > 0 { earned["reward-\(id)"] = max(earned["reward-\(id)"] ?? 0, coins) }
        ownedItemIDs.formUnion(itemIDs)
    }

    /// Takes away items (a refunded purchase), taking them off if worn.
    public mutating func removeItems(_ itemIDs: [String]) {
        ownedItemIDs.subtract(itemIDs)
        equipped = equipped.filter { !itemIDs.contains($0.value) }
    }

    /// Combines this device's wallet with another one (a cloud save). Every
    /// earning and purchase key takes the larger side, so nothing is lost or
    /// counted twice; owned items and opened chests are unioned, and the
    /// outfit stays as worn here unless nothing is worn.
    public func merged(with other: WalletState) -> WalletState {
        var result = self
        result.earned.merge(other.earned) { max($0, $1) }
        result.spent.merge(other.spent) { max($0, $1) }
        result.chestsFound.merge(other.chestsFound) { max($0, $1) }
        result.chestsOpened.merge(other.chestsOpened) { max($0, $1) }
        result.ownedItemIDs.formUnion(other.ownedItemIDs)
        if equipped.isEmpty { result.equipped = other.equipped }
        result.equipped = result.equipped.filter { result.ownedItemIDs.contains($0.value) }
        let otherIsLater = other.day.map { theirs in day.map { theirs > $0 } ?? true } ?? false
        switch (day, other.day) {
        case _ where otherIsLater:
            result.day = other.day
            result.kilometresRewardedToday = other.kilometresRewardedToday
            result.chestsFoundToday = other.chestsFoundToday
        case let (mine?, theirs?) where theirs == mine:
            result.kilometresRewardedToday = max(kilometresRewardedToday, other.kilometresRewardedToday)
            result.chestsFoundToday = max(chestsFoundToday, other.chestsFoundToday)
        default:
            break
        }
        result.openedReferralChestIDs.formUnion(other.openedReferralChestIDs)
        for chest in other.referralChests where !result.referralChests.contains(where: { $0.id == chest.id }) {
            result.referralChests.append(chest)
        }
        result.referralChests.removeAll { result.openedReferralChestIDs.contains($0.id) }
        return result
    }

    /// Pays for a finished rewarded ad. `id` is unique to that one ad view
    /// (the daily limit lives in `AdState`).
    public mutating func earnAdReward(_ coins: Int, id: String) {
        earned["ad-\(id)"] = max(0, coins)
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
    public func owns(itemID: String) -> Bool { ownedItemIDs.contains(itemID) }

    /// Buys something that isn't a walker outfit (e.g. a companion accessory).
    /// Returns false if it's already owned or there aren't enough coins.
    @discardableResult
    public mutating func buy(itemID: String, price: Int) -> Bool {
        guard !ownedItemIDs.contains(itemID), coins >= price else { return false }
        spent["item-\(itemID)"] = price
        ownedItemIDs.insert(itemID)
        return true
    }

    public mutating func buy(_ item: ShopItem) -> PurchaseResult {
        guard !owns(item) else { return .alreadyOwned }
        guard coins >= item.price else { return .notEnoughCoins(needed: item.price - coins) }
        spent["item-\(item.id)"] = item.price
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
        spent["box-\(item.id)"] = price
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
