import Foundation

/// Wildlife, treasures, quests and titles that belong to the team worlds.
/// Kept apart from the solo collection books so their totals never change.
public enum TeamWorldContent {
    public static let creatures: [String: [Creature]] = [
        "enchanted-forest": [
            Creature(id: "glow-moth", name: "Glow Moth", rarity: .common, zoneIDs: ["ef-gate", "ef-glade", "ef-hollow"],
                     personality: "Follows anything that glows, including your torch."),
            Creature(id: "fairy-fox", name: "Fairy Fox", rarity: .rare, zoneIDs: ["ef-glade", "ef-hollow", "ef-heart"],
                     personality: "Leaves tiny sparkles in its pawprints."),
            Creature(id: "elder-stag", name: "Elder Stag", rarity: .epic, zoneIDs: ["ef-heart"],
                     personality: "Its antlers sprout leaves every spring."),
        ],
        "crystal-kingdom": [
            Creature(id: "prism-beetle", name: "Prism Beetle", rarity: .common, zoneIDs: ["ck-steps", "ck-caverns"],
                     personality: "Its shell throws rainbows when it's happy."),
            Creature(id: "frost-penguin", name: "Frost Penguin", rarity: .rare, zoneIDs: ["ck-lake", "ck-throne"],
                     personality: "Slides across the Frozen Mirror for fun."),
            Creature(id: "crystal-drake", name: "Crystal Drake", rarity: .epic, zoneIDs: ["ck-throne"],
                     personality: "A tiny dragon, curled up asleep on the throne."),
        ],
        "forgotten-desert": [
            Creature(id: "fennec", name: "Fennec Fox", rarity: .common, zoneIDs: ["fd-oasis", "fd-mesa"],
                     personality: "Hears your snack bag from three dunes away."),
            Creature(id: "golden-scarab", name: "Golden Scarab", rarity: .rare, zoneIDs: ["fd-ruins", "fd-tomb"],
                     personality: "Rolls a ball of sand bigger than itself."),
            Creature(id: "sphinx-cat", name: "Sphinx Cat", rarity: .epic, zoneIDs: ["fd-tomb"],
                     personality: "Asks riddles, but always gives you a hint."),
        ],
        "floating-isles": [
            Creature(id: "sky-puffin", name: "Sky Puffin", rarity: .common, zoneIDs: ["fi-dock", "fi-meadow"],
                     personality: "Delivers letters between the islands."),
            Creature(id: "kite-ray", name: "Kite Ray", rarity: .rare, zoneIDs: ["fi-falls", "fi-spire"],
                     personality: "Glides between islands like a paper kite."),
            Creature(id: "thunderbird", name: "Thunderbird", rarity: .epic, zoneIDs: ["fi-spire"],
                     personality: "Its wingbeats are the rumble before rain."),
        ],
        "ancient-kingdom": [
            Creature(id: "royal-corgi", name: "Royal Corgi", rarity: .common, zoneIDs: ["ak-road", "ak-castle"],
                     personality: "Thinks the whole kingdom belongs to it."),
            Creature(id: "peacock", name: "Garden Peacock", rarity: .rare, zoneIDs: ["ak-gardens", "ak-bridge"],
                     personality: "Shows off its tail to anyone who walks by."),
            Creature(id: "gargoyle", name: "Little Gargoyle", rarity: .epic, zoneIDs: ["ak-castle"],
                     personality: "Wakes up for one walk a year."),
        ],
    ]

    public static let treasures: [String: Treasure] = [
        "enchanted-forest": Treasure(id: "moonlit-harp", name: "Moonlit Harp", rarity: .epic,
                                     detail: "The forest hums along when you play it."),
        "crystal-kingdom": Treasure(id: "prism-tiara", name: "Prism Tiara", rarity: .epic,
                                    detail: "Turns sunlight into seven tiny rainbows."),
        "forgotten-desert": Treasure(id: "sun-amulet", name: "Sun Amulet", rarity: .epic,
                                     detail: "Warm in your hand, even at night."),
        "floating-isles": Treasure(id: "sky-compass", name: "Sky Compass", rarity: .epic,
                                   detail: "Its needle always points to the next island."),
        "ancient-kingdom": Treasure(id: "royal-seal", name: "Royal Seal", rarity: .legendary,
                                    detail: "Stamps a tiny crown on anything you like."),
    ]

    public static let titles: [String: String] = [
        "enchanted-forest": "Forest Whisperer",
        "crystal-kingdom": "Crystal Keeper",
        "forgotten-desert": "Dune Strider",
        "floating-isles": "Sky Sailor",
        "ancient-kingdom": "Royal Wanderer",
    ]

    public static var allCreatures: [Creature] { TeamWorldCatalog.worlds.flatMap(\.creatures) }

    /// Creatures spotted on `day` in the zones the team has reached. The roll is
    /// a hash of the day and creature, so the whole team sees the same animals.
    public static func sightings(on day: LocalDay, progress: TeamWorldProgress) -> [Creature] {
        let reached = Set(progress.reachedZones.map(\.id))
        return allCreatures.filter { creature in
            creature.zoneIDs.contains(where: reached.contains)
                && WildlifeCatalog.roll("teamwild#\(day.isoString)#\(creature.id)") < creature.dailyChance
        }
    }
}

/// A goal inside one team world.
public struct WorldQuest: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case pathfinder, naturalist, together
    }

    public let kind: Kind
    public let name: String
    public let detail: String
    public let done: Int
    public let goal: Int
    /// Paid once per player. The challenge quest pays through the world's own challenge reward.
    public let reward: Reward
    public let treasure: Treasure?

    public var id: String { reward.id }
    public var isComplete: Bool { done >= goal }
}

extension TeamWorld {
    public var creatures: [Creature] { TeamWorldContent.creatures[id] ?? [] }
    public var treasure: Treasure? { TeamWorldContent.treasures[id] }

    /// Reached every zone, the condition for the world's title.
    public var finalZoneReward: Reward? { zones.last?.reward }

    public func quests(progress: TeamWorldProgress, seenCreatures: Set<String>, challengeDone: Bool) -> [WorldQuest] {
        [
            WorldQuest(kind: .pathfinder, name: "Pathfinder", detail: "Reach every zone of \(name) with your team.",
                       done: progress.reachedZones(in: self).count, goal: zones.count,
                       reward: Reward(id: "teamworld-quest-\(id)-pathfinder", coins: 100, xp: 300), treasure: nil),
            WorldQuest(kind: .naturalist, name: "World Naturalist",
                       detail: "Spot all \(creatures.count) creatures that live in \(name).",
                       done: creatures.filter { seenCreatures.contains($0.id) }.count, goal: creatures.count,
                       reward: Reward(id: "teamworld-quest-\(id)-naturalist", coins: 60, xp: 200), treasure: treasure),
            WorldQuest(kind: .together, name: challenge.name, detail: challenge.detail,
                       done: challengeDone ? 1 : 0, goal: 1, reward: challengeReward, treasure: nil),
        ]
    }
}

extension JournalEvents {
    public static func teamWorldQuest(_ quest: WorldQuest, world: TeamWorld, on day: LocalDay) -> JournalEntry {
        let found = quest.treasure.map { " Found the \($0.name)." } ?? ""
        return JournalEntry(id: quest.reward.id, kind: .expedition, day: day, title: "\(quest.name) complete!",
                            detail: "\(world.name): \(quest.detail)\(found)", iconID: quest.treasure?.spriteID ?? "medal")
    }
}
