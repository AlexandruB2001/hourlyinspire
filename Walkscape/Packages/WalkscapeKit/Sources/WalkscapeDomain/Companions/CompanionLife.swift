import Foundation

// MARK: - Personalities and finds

/// What a companion likes to dig up on walks.
public enum CompanionFindKind: String, Codable, Sendable {
    /// Mossling: stones and minerals.
    case minerals
    /// Emberfox: coins and hidden treasure.
    case treasure
    /// Moonmoth: flowers and night-time wildlife.
    case nightlife
}

/// Something your companion found on today's walk.
public struct CompanionFind: Hashable, Sendable {
    public let day: LocalDay
    public let speciesID: String
    public let title: String
    public let detail: String
    public let coins: Int
    public let xp: Int
    public let treasure: Treasure?
    public let creature: Creature?

    public var reward: Reward { Reward(id: "companion-find-\(day.isoString)", coins: coins, xp: xp) }
}

public enum CompanionPersonality {
    public static func findKind(for speciesID: String) -> CompanionFindKind {
        switch speciesID {
        case "emberfox": return .treasure
        case "moonmoth": return .nightlife
        default: return .minerals
        }
    }

    /// Chance per day (once you've walked a kilometre) that your companion finds something.
    public static let dailyFindChance = 0.25

    /// Today's find, if any. Fixed per day, so it can only be collected once.
    public static func find(speciesID: String, day: LocalDay, metersToday: Int,
                            ownedTreasures: Set<String>, seenCreatures: Set<String>) -> CompanionFind? {
        guard metersToday >= 1_000, WildlifeCatalog.roll("companion#\(day.isoString)#\(speciesID)") < dailyFindChance else {
            return nil
        }
        let luck = WildlifeCatalog.roll("companion-luck#\(day.isoString)#\(speciesID)")
        let name = CompanionCatalog.species(withID: speciesID)?.name ?? "Your companion"
        switch findKind(for: speciesID) {
        case .minerals:
            let stones = Set(["amber", "ruby", "pearl"])
            let treasure = luck < 0.12
                ? TreasureCatalog.pick(seed: "companion-\(day.isoString)", excluding: ownedTreasures.union(
                    TreasureCatalog.all.map(\.id).filter { !stones.contains($0) }))
                : nil
            return CompanionFind(day: day, speciesID: speciesID,
                                 title: treasure.map { "\(name) dug up the \($0.name)!" } ?? "\(name) found a shiny stone",
                                 detail: "It turned it over very slowly, then gave it to you.",
                                 coins: 15, xp: 40, treasure: treasure, creature: nil)
        case .treasure:
            let treasure = luck < 0.10 ? TreasureCatalog.pick(seed: "companion-\(day.isoString)", excluding: ownedTreasures) : nil
            let coins = 20 + Int(luck * 20)
            return CompanionFind(day: day, speciesID: speciesID,
                                 title: treasure.map { "\(name) sniffed out the \($0.name)!" } ?? "\(name) found \(coins) coins",
                                 detail: "It came bounding back, very pleased with itself.",
                                 coins: coins, xp: 40, treasure: treasure, creature: nil)
        case .nightlife:
            let night = ["owl", "deer", "aurora-moth", "firefly-sprite", "bat", "wisp"]
                .compactMap(WildlifeCatalog.creature(withID:)).filter { !seenCreatures.contains($0.id) }
            let creature = luck < 0.15 && !night.isEmpty ? night[Int(luck / 0.15 * Double(night.count)) % night.count] : nil
            return CompanionFind(day: day, speciesID: speciesID,
                                 title: creature.map { "\(name) led you to a \($0.name)!" } ?? "\(name) found a moonflower",
                                 detail: "It fluttered back with pollen on its wings.",
                                 coins: 12, xp: 40, treasure: nil, creature: creature)
        }
    }
}

// MARK: - Voice

/// Little lines companions say, each in their own personality.
public enum CompanionVoice {
    public enum Situation: Hashable, Sendable {
        case resting
        case walking
        case newZone(String)
        case levelUp(Int)
        case evolved(CompanionGrowth.Stage)
    }

    static let lines: [String: (resting: [String], walking: [String], zone: String, level: String, evolved: String)] = [
        "mossling": (["Mossling is sitting very still. Waiting for you.", "A little moss grew on Mossling today."],
                     ["Mossling plods along, one steady step at a time.", "Mossling hums a low, rumbly tune."],
                     "Mossling stops to feel the ground of %@.", "Mossling nods slowly. Level %@. Well done.",
                     "Mossling's runes glow. It's a %@ now."),
        "emberfox": (["Emberfox is bouncing. Shall we go for a walk?", "Emberfox chased its tail. Twice."],
                     ["Emberfox zooms ahead, then waits for you.", "Emberfox sniffs every single flower."],
                     "Emberfox races into %@!", "Emberfox does a happy spin! Level %@!",
                     "Emberfox's tail sparks. It's a %@ now!"),
        "moonmoth": (["Moonmoth is dozing on a petal.", "Moonmoth is dreaming of starlight."],
                     ["Moonmoth flutters along beside you.", "Moonmoth dusts the path with moonlight."],
                     "Moonmoth drifts quietly into %@.", "Moonmoth glows softly. Level %@.",
                     "Moonmoth's wings shimmer. It's a %@ now."),
    ]

    public static func line(speciesID: String, situation: Situation, day: LocalDay) -> String {
        guard let set = lines[speciesID] else { return "" }
        let pick = Int(WildlifeCatalog.roll("voice#\(day.isoString)#\(speciesID)") * 2) % 2
        switch situation {
        case .resting: return set.resting[pick]
        case .walking: return set.walking[pick]
        case .newZone(let zone): return set.zone.replacingOccurrences(of: "%@", with: zone)
        case .levelUp(let level): return set.level.replacingOccurrences(of: "%@", with: "\(level)")
        case .evolved(let stage): return set.evolved.replacingOccurrences(of: "%@", with: stage.name)
        }
    }
}

// MARK: - Accessories

public struct CompanionAccessory: Identifiable, Hashable, Sendable {
    public enum Slot: String, CaseIterable, Codable, Sendable {
        case head, neck, back
    }

    public let id: String
    public let name: String
    public let slot: Slot
    /// Coins in the shop; nil when it can only be earned.
    public let price: Int?
    /// Explorer Level that gives it for free, if any.
    public let unlockLevel: Int?
    /// Seasonal event that gives it. While that event runs it can only be
    /// earned; afterwards it joins the shop, so nobody misses it forever.
    public let eventID: String?

    public init(id: String, name: String, slot: Slot, price: Int?, unlockLevel: Int? = nil, eventID: String? = nil) {
        self.id = id
        self.name = name
        self.slot = slot
        self.price = price
        self.unlockLevel = unlockLevel
        self.eventID = eventID
    }

    /// Whether it can be bought with coins on `day`.
    public func isForSale(on day: LocalDay) -> Bool {
        guard price != nil else { return false }
        return !SeasonalEventCatalog.isEventExclusiveNow(id, on: day)
    }
}

public enum CompanionAccessoryCatalog {
    public static let all: [CompanionAccessory] = [
        CompanionAccessory(id: "pet-bow", name: "Ribbon Bow", slot: .head, price: nil, unlockLevel: 5),
        CompanionAccessory(id: "pet-straw-hat", name: "Tiny Straw Hat", slot: .head, price: 120),
        CompanionAccessory(id: "pet-beanie", name: "Tiny Beanie", slot: .head, price: 120),
        CompanionAccessory(id: "pet-flower-crown", name: "Flower Crown", slot: .head, price: 200),
        CompanionAccessory(id: "pet-crown", name: "Little Crown", slot: .head, price: nil, unlockLevel: 15),
        CompanionAccessory(id: "pet-red-scarf", name: "Red Scarf", slot: .neck, price: 100),
        CompanionAccessory(id: "pet-blue-scarf", name: "Blue Scarf", slot: .neck, price: 100),
        CompanionAccessory(id: "pet-bell", name: "Golden Bell", slot: .neck, price: nil, unlockLevel: 10),
        CompanionAccessory(id: "pet-backpack", name: "Mini Backpack", slot: .back, price: 180),
        CompanionAccessory(id: "pet-cape", name: "Hero Cape", slot: .back, price: 250),
        CompanionAccessory(id: "pet-pumpkin-hat", name: "Pumpkin Hat", slot: .head, price: 300, eventID: "great-harvest"),
        CompanionAccessory(id: "pet-snow-hat", name: "Snowy Bobble Hat", slot: .head, price: 300, eventID: "winter-wanderer"),
        CompanionAccessory(id: "pet-petal-crown", name: "Petal Crown", slot: .head, price: 300, eventID: "spring-awakening"),
        CompanionAccessory(id: "pet-sailor-hat", name: "Sailor Hat", slot: .head, price: 300, eventID: "ocean-expedition"),
        CompanionAccessory(id: "pet-star-cape", name: "Starfall Cape", slot: .back, price: 300, eventID: "starfall-festival"),
    ]

    public static func accessory(withID id: String) -> CompanionAccessory? { all.first { $0.id == id } }

    /// Accessories given for free at `level`.
    public static func unlocked(atLevel level: Int) -> [CompanionAccessory] { all.filter { $0.unlockLevel == level } }
}

extension JournalEvents {
    public static func companionFind(_ find: CompanionFind) -> JournalEntry {
        JournalEntry(id: "companion-find-\(find.day.isoString)", kind: .companion, day: find.day, title: find.title,
                     detail: find.detail, iconID: find.treasure?.spriteID ?? find.creature?.spriteID ?? "companion:\(find.speciesID):0")
    }
}
