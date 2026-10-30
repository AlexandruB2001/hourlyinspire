import Foundation

/// The five collection books. Relics are the existing zone discoveries.
public enum CollectionCategory: String, CaseIterable, Codable, Sendable {
    case relics, wildlife, postcards, treasures, memories

    public var displayName: String {
        switch self {
        case .relics: return "Relics"
        case .wildlife: return "Wildlife"
        case .postcards: return "Postcards"
        case .treasures: return "Treasures"
        case .memories: return "Memories"
        }
    }
}

// MARK: - Wildlife

public struct Creature: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rarity: Rarity
    /// Zones it can be spotted in.
    public let zoneIDs: [String]
    public let personality: String
    public let spriteID: String

    public init(id: String, name: String, rarity: Rarity, zoneIDs: [String], personality: String, spriteID: String? = nil) {
        self.id = id
        self.name = name
        self.rarity = rarity
        self.zoneIDs = zoneIDs
        self.personality = personality
        self.spriteID = spriteID ?? id
    }

    /// Chance per day of spotting it, once you've reached one of its zones that day.
    public var dailyChance: Double {
        switch rarity {
        case .common: return 0.30
        case .rare: return 0.12
        case .epic: return 0.05
        case .legendary: return 0.015
        }
    }

    public var reward: Reward {
        let (coins, xp): (Int, Int)
        switch rarity {
        case .common: (coins, xp) = (10, 40)
        case .rare: (coins, xp) = (20, 70)
        case .epic: (coins, xp) = (35, 110)
        case .legendary: (coins, xp) = (60, 200)
        }
        return Reward(id: "wildlife-\(id)", coins: coins, xp: xp)
    }
}

public enum WildlifeCatalog {
    public static let all: [Creature] = [
        Creature(id: "rabbit", name: "Meadow Rabbit", rarity: .common, zoneIDs: ["meadow", "rolling-hills"],
                 personality: "Twitchy nose, big heart. Always the first to say hello."),
        Creature(id: "bee", name: "Bumble Bee", rarity: .common, zoneIDs: ["meadow", "lavender-fields"],
                 personality: "Hums a little tune for every flower it visits."),
        Creature(id: "otter", name: "River Otter", rarity: .common, zoneIDs: ["riverside"],
                 personality: "Floats on its back and juggles pebbles for fun."),
        Creature(id: "kingfisher", name: "Kingfisher", rarity: .rare, zoneIDs: ["riverside", "lakeside"],
                 personality: "A flash of blue. Blink and you'll miss it."),
        Creature(id: "owl", name: "Forest Owl", rarity: .rare, zoneIDs: ["pine-forest", "maple-woods"],
                 personality: "Wise, sleepy, and secretly very curious about you."),
        Creature(id: "squirrel", name: "Red Squirrel", rarity: .common, zoneIDs: ["pine-forest", "maple-woods"],
                 personality: "Has hidden acorns everywhere and remembers about half of them."),
        Creature(id: "sheep", name: "Woolly Sheep", rarity: .common, zoneIDs: ["rolling-hills"],
                 personality: "Fluffy, calm and very good at standing still."),
        Creature(id: "frog", name: "Lily Frog", rarity: .common, zoneIDs: ["lakeside", "firefly-marsh"],
                 personality: "Sings the loudest at dusk, slightly off-key."),
        Creature(id: "swan", name: "Mirror Swan", rarity: .rare, zoneIDs: ["lakeside"],
                 personality: "Glides so smoothly the lake barely ripples."),
        Creature(id: "cat", name: "Village Cat", rarity: .common, zoneIDs: ["village"],
                 personality: "Owns every windowsill in Hearth Village."),
        Creature(id: "bat", name: "Cave Bat", rarity: .common, zoneIDs: ["crystal-caves"],
                 personality: "Hangs around upside down, telling echoing jokes."),
        Creature(id: "wisp", name: "Crystal Wisp", rarity: .epic, zoneIDs: ["crystal-caves"],
                 personality: "A spark of crystal light that follows kind walkers."),
        Creature(id: "snow-fox", name: "Snow Fox", rarity: .rare, zoneIDs: ["snowy-ridge", "starlight-pass"],
                 personality: "Pounces into snowdrifts and pops out grinning."),
        Creature(id: "turtle", name: "Moss Turtle", rarity: .rare, zoneIDs: ["cloud-forest"],
                 personality: "Carries a tiny garden on its shell. In no hurry at all."),
        Creature(id: "spirit", name: "Forest Spirit", rarity: .legendary, zoneIDs: ["cloud-forest"],
                 personality: "Ancient and gentle. Few walkers have ever seen one."),
        Creature(id: "goat", name: "Mountain Goat", rarity: .rare, zoneIDs: ["summit", "snowy-ridge"],
                 personality: "Stands on ledges that make everyone else nervous."),
        Creature(id: "aurora-moth", name: "Aurora Moth", rarity: .epic, zoneIDs: ["starlight-pass"],
                 personality: "Its wings shimmer with the colours of the northern lights."),
        Creature(id: "snow-monkey", name: "Snow Monkey", rarity: .rare, zoneIDs: ["hot-springs"],
                 personality: "Soaks in the warm pools with a very serious face."),
        Creature(id: "hedgehog", name: "Hedgehog", rarity: .common, zoneIDs: ["maple-woods", "blossom-orchard"],
                 personality: "Rolls through fallen leaves and collects them on its spines."),
        Creature(id: "panda", name: "Panda Cub", rarity: .epic, zoneIDs: ["bamboo-grove"],
                 personality: "Tumbles more than it walks. Always snacking."),
        Creature(id: "butterfly", name: "Blossom Butterfly", rarity: .common, zoneIDs: ["blossom-orchard", "lavender-fields"],
                 personality: "Dances from petal to petal without a care."),
        Creature(id: "deer", name: "Moonlit Deer", rarity: .epic, zoneIDs: ["lavender-fields", "firefly-marsh"],
                 personality: "Appears at twilight, silent as moonlight."),
        Creature(id: "lizard", name: "Canyon Lizard", rarity: .common, zoneIDs: ["red-canyon"],
                 personality: "Sunbathes on warm rocks and does push-ups to say hi."),
        Creature(id: "firefly-sprite", name: "Firefly Sprite", rarity: .epic, zoneIDs: ["firefly-marsh"],
                 personality: "Leads lost walkers home with its little lantern glow."),
        Creature(id: "crab", name: "Hermit Crab", rarity: .common, zoneIDs: ["sandy-shore"],
                 personality: "Always shopping for a slightly bigger shell."),
        Creature(id: "gull", name: "Harbour Gull", rarity: .common, zoneIDs: ["sandy-shore", "lighthouse-point"],
                 personality: "Will absolutely try to steal your snack."),
        Creature(id: "whale", name: "Sunset Whale", rarity: .legendary, zoneIDs: ["lighthouse-point"],
                 personality: "Breaches once at sunset, then sings into the deep."),
    ]

    public static func creature(withID id: String) -> Creature? { all.first { $0.id == id } }

    /// Creatures spotted on `day` among the zones reached that day. The roll
    /// is a hash of the day and creature, so it's the same for everyone and
    /// however often the app recalculates; walking further only adds zones.
    public static func sightings(on day: LocalDay, zonesReached: [String]) -> [Creature] {
        let reached = Set(zonesReached)
        return all.filter { creature in
            guard creature.zoneIDs.contains(where: reached.contains) else { return false }
            return roll("wildlife#\(day.isoString)#\(creature.id)") < creature.dailyChance
        }
    }

    /// A number in 0..<1 fixed by `seed`.
    public static func roll(_ seed: String) -> Double {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        // Mix the bits so similar seeds don't give similar numbers.
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        return Double(hash % 1_000_000) / 1_000_000
    }
}

// MARK: - Treasures

public struct Treasure: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rarity: Rarity
    public let detail: String
    public let spriteID: String

    public init(id: String, name: String, rarity: Rarity, detail: String, spriteID: String? = nil) {
        self.id = id
        self.name = name
        self.rarity = rarity
        self.detail = detail
        self.spriteID = spriteID ?? id
    }

    public var reward: Reward {
        let (coins, xp): (Int, Int)
        switch rarity {
        case .common: (coins, xp) = (15, 50)
        case .rare: (coins, xp) = (25, 80)
        case .epic: (coins, xp) = (40, 120)
        case .legendary: (coins, xp) = (75, 220)
        }
        return Reward(id: "treasure-\(id)", coins: coins, xp: xp)
    }
}

public enum TreasureCatalog {
    public static let all: [Treasure] = [
        Treasure(id: "golden-acorn", name: "Golden Acorn", rarity: .common, detail: "Some squirrel is going to be very upset."),
        Treasure(id: "amber", name: "Amber Drop", rarity: .common, detail: "A tiny leaf is trapped inside, forever autumn."),
        Treasure(id: "pearl", name: "Moon Pearl", rarity: .rare, detail: "It glows faintly whenever the moon is out."),
        Treasure(id: "old-map", name: "Old Map", rarity: .rare, detail: "Someone marked a spot with a little red cross."),
        Treasure(id: "music-box", name: "Music Box", rarity: .epic, detail: "Plays a lullaby that everyone half-remembers."),
        Treasure(id: "ruby", name: "Canyon Ruby", rarity: .epic, detail: "Warm to the touch, like a coal from a campfire."),
        Treasure(id: "star-shard", name: "Star Shard", rarity: .epic, detail: "A sliver of a falling star. It hums softly."),
        Treasure(id: "crown-jewel", name: "Lost Crown", rarity: .legendary, detail: "The crown of a forgotten wandering king."),
    ]

    public static func treasure(withID id: String) -> Treasure? { all.first { $0.id == id } }

    /// A treasure you don't own yet, chosen by `seed` with rarer ones less likely.
    public static func pick(seed: String, excluding owned: Set<String>) -> Treasure? {
        let left = all.filter { !owned.contains($0.id) }
        guard !left.isEmpty else { return nil }
        let weights = left.map { treasure -> Double in
            switch treasure.rarity {
            case .common: return 6
            case .rare: return 3
            case .epic: return 1.5
            case .legendary: return 0.5
            }
        }
        var target = WildlifeCatalog.roll("treasure#\(seed)") * weights.reduce(0, +)
        for (treasure, weight) in zip(left, weights) {
            if target < weight { return treasure }
            target -= weight
        }
        return left.last
    }

    /// Chance that a trail chest also holds a treasure.
    public static let chestTreasureChance = 0.04
}

// MARK: - Postcards

/// A scenic snapshot of a zone, earned by coming back to it on several
/// different days (rewarding return visits rather than longer walks).
public struct Postcard: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let zoneID: String
    public let visitsNeeded: Int
    public let caption: String

    public init(id: String, title: String, zoneID: String, visitsNeeded: Int, caption: String) {
        self.id = id
        self.title = title
        self.zoneID = zoneID
        self.visitsNeeded = visitsNeeded
        self.caption = caption
    }

    public var reward: Reward { Reward(id: "postcard-\(id)", coins: 15, xp: 50) }
}

public enum PostcardCatalog {
    public static let all: [Postcard] = [
        Postcard(id: "meadow-morning", title: "Meadow Morning", zoneID: "meadow", visitsNeeded: 7,
                 caption: "Seven mornings of wildflowers and birdsong."),
        Postcard(id: "river-bridge", title: "The Creaky Bridge", zoneID: "riverside", visitsNeeded: 5,
                 caption: "You know every creak of this bridge by now."),
        Postcard(id: "pine-light", title: "Pine Light", zoneID: "pine-forest", visitsNeeded: 5,
                 caption: "Golden beams through the tall pines."),
        Postcard(id: "lake-mirror", title: "Lake Mirror", zoneID: "lakeside", visitsNeeded: 4,
                 caption: "The mountains floating upside down, again."),
        Postcard(id: "hearth-lanes", title: "Hearth Lanes", zoneID: "village", visitsNeeded: 3,
                 caption: "The baker waves. You're a regular now."),
        Postcard(id: "crystal-glow", title: "Crystal Glow", zoneID: "crystal-caves", visitsNeeded: 3,
                 caption: "The crystals pulse a little brighter for you."),
        Postcard(id: "summit-view", title: "Above the Clouds", zoneID: "summit", visitsNeeded: 2,
                 caption: "The whole world, all at once. Twice!"),
        Postcard(id: "aurora-night", title: "Aurora Night", zoneID: "starlight-pass", visitsNeeded: 2,
                 caption: "Green ribbons of light over the pass."),
        Postcard(id: "spring-steam", title: "Spring Steam", zoneID: "hot-springs", visitsNeeded: 2,
                 caption: "Warm pools and stone lanterns."),
        Postcard(id: "petal-path", title: "Petal Path", zoneID: "blossom-orchard", visitsNeeded: 2,
                 caption: "Pink petals all the way down the lane."),
        Postcard(id: "marsh-lights", title: "Marsh Lights", zoneID: "firefly-marsh", visitsNeeded: 2,
                 caption: "A thousand fireflies blinking hello."),
        Postcard(id: "lighthouse-sunset", title: "Lighthouse Sunset", zoneID: "lighthouse-point", visitsNeeded: 2,
                 caption: "The beam sweeping over a golden sea."),
    ]

    public static func postcard(withID id: String) -> Postcard? { all.first { $0.id == id } }
}

// MARK: - Memories

/// A personal milestone, worked out from your walking history.
public struct Memory: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let spriteID: String
}

public enum MemoryCatalog {
    enum Rule {
        case firstDay(meters: Int)
        case lifetime(meters: Int)
        case activeDays(Int)
    }

    static let rules: [(Memory, Rule)] = [
        (Memory(id: "first-km", title: "The First Kilometre", detail: "The day it all began.", spriteID: "boot"), .firstDay(meters: 1_000)),
        (Memory(id: "first-5k", title: "A Proper Adventure", detail: "Your first 5 km day.", spriteID: "compass"), .firstDay(meters: 5_000)),
        (Memory(id: "first-10k", title: "Double Digits", detail: "Your first 10 km day.", spriteID: "star"), .firstDay(meters: 10_000)),
        (Memory(id: "first-20k", title: "Coast to Summit", detail: "Your first 20 km day.", spriteID: "starfall"), .firstDay(meters: 20_000)),
        (Memory(id: "total-10k", title: "10 km Together", detail: "10 km walked in total.", spriteID: "boot"), .lifetime(meters: 10_000)),
        (Memory(id: "total-50k", title: "50 km of Stories", detail: "50 km walked in total.", spriteID: "map"), .lifetime(meters: 50_000)),
        (Memory(id: "total-100k", title: "The Hundred", detail: "100 km walked in total.", spriteID: "medal"), .lifetime(meters: 100_000)),
        (Memory(id: "total-250k", title: "Long Road", detail: "250 km walked in total.", spriteID: "flag"), .lifetime(meters: 250_000)),
        (Memory(id: "total-500k", title: "Half a Thousand", detail: "500 km walked in total.", spriteID: "spyglass"), .lifetime(meters: 500_000)),
        (Memory(id: "days-10", title: "A Habit Forms", detail: "Walked 1 km on 10 different days.", spriteID: "clover"), .activeDays(10)),
        (Memory(id: "days-50", title: "Fifty Wanders", detail: "Walked 1 km on 50 different days.", spriteID: "lantern"), .activeDays(50)),
        (Memory(id: "days-100", title: "A Hundred Days", detail: "Walked 1 km on 100 different days.", spriteID: "crystal"), .activeDays(100)),
    ]

    public static var all: [Memory] { rules.map(\.0) }

    /// Memories reached, with the day each one happened.
    public static func reached(in progression: ProgressionState) -> [String: LocalDay] {
        let days = progression.dailyBestMeters.compactMap { key, meters in LocalDay(isoString: key).map { ($0, meters) } }
            .sorted { $0.0 < $1.0 }
        var result: [String: LocalDay] = [:]
        for (memory, rule) in rules {
            var total = 0
            var active = 0
            for (day, meters) in days {
                total += meters
                if meters >= 1_000 { active += 1 }
                let met: Bool
                switch rule {
                case .firstDay(let target): met = meters >= target
                case .lifetime(let target): met = total >= target
                case .activeDays(let count): met = active >= count
                }
                if met {
                    result[memory.id] = day
                    break
                }
            }
        }
        return result
    }
}

// MARK: - State

/// What has been found that isn't derived from progression: wildlife and
/// treasures, with the day each was first found. Postcards and memories are
/// worked out from walking history, so they can't drift out of sync.
public struct CollectionState: Codable, Hashable, Sendable {
    public private(set) var wildlife: [String: LocalDay]
    public private(set) var treasures: [String: LocalDay]

    public init() {
        wildlife = [:]
        treasures = [:]
    }

    enum CodingKeys: String, CodingKey { case wildlife, treasures }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wildlife = try container.decodeIfPresent([String: LocalDay].self, forKey: .wildlife) ?? [:]
        treasures = try container.decodeIfPresent([String: LocalDay].self, forKey: .treasures) ?? [:]
    }

    /// Records today's sightings. Returns only creatures seen for the first time.
    @discardableResult
    public mutating func recordSightings(_ creatures: [Creature], on day: LocalDay) -> [Creature] {
        creatures.filter { creature in
            guard wildlife[creature.id] == nil else { return false }
            wildlife[creature.id] = day
            return true
        }
    }

    /// Records a treasure. Returns false if it was already found.
    @discardableResult
    public mutating func recordTreasure(_ treasure: Treasure, on day: LocalDay) -> Bool {
        guard treasures[treasure.id] == nil else { return false }
        treasures[treasure.id] = day
        return true
    }

    /// Two phones' collections together, keeping the earliest discovery date.
    public func merged(with other: CollectionState) -> CollectionState {
        var result = self
        result.wildlife.merge(other.wildlife) { min($0, $1) }
        result.treasures.merge(other.treasures) { min($0, $1) }
        return result
    }
}

/// Postcards earned so far, with the day each was earned.
public enum Postcards {
    public static func earned(in progression: ProgressionState, catalog: ZoneCatalog = .standard) -> [String: LocalDay] {
        let days = progression.dailyBestMeters.compactMap { key, meters in LocalDay(isoString: key).map { ($0, meters) } }
            .sorted { $0.0 < $1.0 }
        var result: [String: LocalDay] = [:]
        for postcard in PostcardCatalog.all {
            guard let zone = catalog.zones.first(where: { $0.id == postcard.zoneID }) else { continue }
            var visits = 0
            for (day, meters) in days where meters >= zone.startMeters {
                visits += 1
                if visits >= postcard.visitsNeeded {
                    result[postcard.id] = day
                    break
                }
            }
        }
        return result
    }
}

/// Progress through one collection book.
public struct CollectionProgress: Hashable, Sendable {
    public let category: CollectionCategory
    public let found: Int
    public let total: Int

    public init(category: CollectionCategory, found: Int, total: Int) {
        self.category = category
        self.found = max(0, found)
        self.total = max(0, total)
    }

    public var fraction: Double { total == 0 ? 0 : Double(found) / Double(total) }
    public var percent: Int { Int((fraction * 100).rounded(.down)) }

    /// Milestone rewards at 25 / 50 / 75 / 100 %.
    public static let milestones = [25, 50, 75, 100]

    public var milestoneRewards: [Reward] {
        Self.milestones.filter { percent >= $0 }.map { milestone in
            Reward(id: "collection-\(category.rawValue)-\(milestone)", coins: milestone, xp: milestone * 3)
        }
    }
}

extension JournalEvents {
    public static func wildlife(_ creature: Creature, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "wildlife-\(creature.id)", kind: .wildlife, day: day, title: "Spotted a \(creature.name)",
                     detail: creature.personality, iconID: creature.spriteID)
    }

    public static func treasure(_ treasure: Treasure, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "treasure-\(treasure.id)", kind: .treasure, day: day, title: "Found the \(treasure.name)",
                     detail: treasure.detail, iconID: treasure.spriteID)
    }

    public static func postcard(_ postcard: Postcard, on day: LocalDay, catalog: ZoneCatalog = .standard) -> JournalEntry {
        let biome = catalog.zones.first { $0.id == postcard.zoneID }?.biome.rawValue ?? "meadow"
        return JournalEntry(id: "postcard-\(postcard.id)", kind: .postcard, day: day, title: "Postcard: \(postcard.title)",
                            detail: postcard.caption, iconID: "zone:\(biome)")
    }
}
