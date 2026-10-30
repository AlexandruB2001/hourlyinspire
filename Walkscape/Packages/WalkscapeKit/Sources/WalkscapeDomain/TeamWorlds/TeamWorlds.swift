import Foundation

/// The colour mood of a team world, applied over the zone's biome art.
public enum WorldTint: String, Codable, CaseIterable, Sendable {
    case enchanted, crystal, desert, skyward, ancient
}

/// A zone inside a team world.
public struct TeamWorldZone: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tagline: String
    public let biome: Biome
    /// Team distance (after the world opens) needed to reach this zone.
    public let metersFromWorldStart: Int
    public let relic: Collectible

    public init(id: String, name: String, tagline: String, biome: Biome, metersFromWorldStart: Int, relic: Collectible) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.biome = biome
        self.metersFromWorldStart = metersFromWorldStart
        self.relic = relic
    }

    /// Paid once per player, ever (moving teams can't collect it again).
    public var reward: Reward { Reward(id: "teamworld-zone-\(id)", coins: 40, xp: 150) }
}

/// The world's closing community challenge: walk this far together within a week.
public struct WorldChallenge: Hashable, Sendable {
    public let name: String
    public let detail: String
    public let weekMeters: Int
}

/// A shared world a team explores together, far beyond any one walker's day.
public struct TeamWorld: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tagline: String
    public let tint: WorldTint
    public let zones: [TeamWorldZone]
    public let challenge: WorldChallenge

    /// Team distance from opening the world to its last zone.
    public var lengthMeters: Int { zones.last?.metersFromWorldStart ?? 0 }

    public var challengeReward: Reward { Reward(id: "teamworld-final-\(id)", coins: 150, xp: 500) }
}

public enum TeamWorldCatalog {
    /// Team worlds open after the team finishes this expedition.
    public static let unlockExpeditionID = "summit-relay"
    /// A player must have walked at least this far for the team to collect world rewards.
    public static let minimumContribution = 2_000

    static func relic(_ id: String, _ name: String, _ detail: String, _ sprite: String) -> Collectible {
        Collectible(id: id, name: name, detail: detail, spriteID: sprite)
    }

    public static let worlds: [TeamWorld] = [
        TeamWorld(id: "enchanted-forest", name: "The Enchanted Forest", tagline: "Where the trees whisper back.", tint: .enchanted,
                  zones: [
                    TeamWorldZone(id: "ef-gate", name: "Moonlit Gate", tagline: "Two ancient trees form an archway of light.",
                                  biome: .pineForest, metersFromWorldStart: 0,
                                  relic: relic("ef-acorn", "Silver Acorn", "It chimes softly when shaken.", "golden-acorn")),
                    TeamWorldZone(id: "ef-glade", name: "Glowcap Glade", tagline: "Mushrooms glow in every colour.",
                                  biome: .cloudForest, metersFromWorldStart: 100_000,
                                  relic: relic("ef-cap", "Rainbow Glowcap", "Each spot glows a different colour.", "mushroom")),
                    TeamWorldZone(id: "ef-brook", name: "Singing Brook", tagline: "The water hums a lullaby.",
                                  biome: .riverside, metersFromWorldStart: 250_000,
                                  relic: relic("ef-stone", "Humming Stone", "Hold it close and it hums along.", "stone")),
                    TeamWorldZone(id: "ef-hollow", name: "Fairy Hollow", tagline: "Tiny lanterns hang from every branch.",
                                  biome: .fireflyMarsh, metersFromWorldStart: 450_000,
                                  relic: relic("ef-lantern", "Fairy Lantern", "Its flame is the size of a firefly.", "lantern")),
                    TeamWorldZone(id: "ef-heart", name: "Heartwood", tagline: "The oldest tree in any world.",
                                  biome: .autumnWoods, metersFromWorldStart: 700_000,
                                  relic: relic("ef-seed", "Heartwood Seed", "A new forest, waiting to happen.", "pinecone")),
                  ],
                  challenge: WorldChallenge(name: "Wake the Ancient Tree",
                                            detail: "Walk 60 km together in one week to wake the Heartwood.", weekMeters: 60_000)),
        TeamWorld(id: "crystal-kingdom", name: "Crystal Kingdom", tagline: "A palace carved from living crystal.", tint: .crystal,
                  zones: [
                    TeamWorldZone(id: "ck-steps", name: "Prism Steps", tagline: "Every step throws a rainbow.",
                                  biome: .snowyRidge, metersFromWorldStart: 0,
                                  relic: relic("ck-prism", "Pocket Prism", "Light comes out a different colour.", "crystal")),
                    TeamWorldZone(id: "ck-caverns", name: "Echo Caverns", tagline: "Your footsteps echo as music.",
                                  biome: .crystalCaves, metersFromWorldStart: 150_000,
                                  relic: relic("ck-bell", "Crystal Bell", "It rings without being touched.", "pearl")),
                    TeamWorldZone(id: "ck-lake", name: "Frozen Mirror", tagline: "A lake of perfect ice.",
                                  biome: .lakeside, metersFromWorldStart: 350_000,
                                  relic: relic("ck-flake", "Eternal Snowflake", "It never melts, not even in your hand.", "snowflake")),
                    TeamWorldZone(id: "ck-throne", name: "Crystal Throne", tagline: "The crystal queen's empty throne.",
                                  biome: .summit, metersFromWorldStart: 600_000,
                                  relic: relic("ck-gem", "Queen's Gem", "It glows when your team walks together.", "ruby")),
                  ],
                  challenge: WorldChallenge(name: "Light the Crystal Crown",
                                            detail: "Walk 75 km together in one week to light the crown.", weekMeters: 75_000)),
        TeamWorld(id: "forgotten-desert", name: "Forgotten Desert", tagline: "Golden dunes over buried cities.", tint: .desert,
                  zones: [
                    TeamWorldZone(id: "fd-oasis", name: "Palm Oasis", tagline: "Cool water under swaying palms.",
                                  biome: .sandyShore, metersFromWorldStart: 0,
                                  relic: relic("fd-shell", "Desert Shell", "From a sea that dried up long ago.", "shell")),
                    TeamWorldZone(id: "fd-mesa", name: "Sunset Mesa", tagline: "Red rocks glowing at dusk.",
                                  biome: .redCanyon, metersFromWorldStart: 150_000,
                                  relic: relic("fd-agate", "Sun Agate", "Warm, like it remembers the sun.", "agate")),
                    TeamWorldZone(id: "fd-ruins", name: "Sand-Swept Ruins", tagline: "Pillars of a forgotten city.",
                                  biome: .village, metersFromWorldStart: 400_000,
                                  relic: relic("fd-map", "Ruin Map", "Shows a city that no longer exists.", "old-map")),
                    TeamWorldZone(id: "fd-tomb", name: "Starlit Tomb", tagline: "Where an old king watches the stars.",
                                  biome: .starlightPass, metersFromWorldStart: 700_000,
                                  relic: relic("fd-crown", "Sand King's Crown", "Still waiting for its king.", "crown-jewel")),
                  ],
                  challenge: WorldChallenge(name: "Raise the Sun Gate",
                                            detail: "Walk 80 km together in one week to open the gate.", weekMeters: 80_000)),
        TeamWorld(id: "floating-isles", name: "Floating Isles", tagline: "Islands drifting above the clouds.", tint: .skyward,
                  zones: [
                    TeamWorldZone(id: "fi-dock", name: "Cloud Dock", tagline: "Where the sky-boats tie up.",
                                  biome: .lighthousePoint, metersFromWorldStart: 0,
                                  relic: relic("fi-feather", "Sky Feather", "It floats gently upward.", "feather")),
                    TeamWorldZone(id: "fi-meadow", name: "Sky Meadow", tagline: "Flowers that grow on clouds.",
                                  biome: .meadow, metersFromWorldStart: 200_000,
                                  relic: relic("fi-clover", "Cloud Clover", "Five leaves, extra lucky.", "clover")),
                    TeamWorldZone(id: "fi-falls", name: "Upside Falls", tagline: "A waterfall that flows to the sky.",
                                  biome: .hotSprings, metersFromWorldStart: 450_000,
                                  relic: relic("fi-bottle", "Bottled Cloud", "A tiny storm, safely corked.", "bottle")),
                    TeamWorldZone(id: "fi-spire", name: "Wind Spire", tagline: "The highest point of any world.",
                                  biome: .summit, metersFromWorldStart: 750_000,
                                  relic: relic("fi-star", "Star Shard", "Still humming from the sky.", "star-shard")),
                  ],
                  challenge: WorldChallenge(name: "Ride the Great Wind",
                                            detail: "Walk 90 km together in one week to catch the wind.", weekMeters: 90_000)),
        TeamWorld(id: "ancient-kingdom", name: "Ancient Kingdom", tagline: "A grand old kingdom, waiting to wake.", tint: .ancient,
                  zones: [
                    TeamWorldZone(id: "ak-road", name: "King's Road", tagline: "Stone paths worn smooth by time.",
                                  biome: .rollingHills, metersFromWorldStart: 0,
                                  relic: relic("ak-coin", "Old Crown Coin", "Stamped with a smiling king.", "coin")),
                    TeamWorldZone(id: "ak-gardens", name: "Royal Gardens", tagline: "Hedges shaped like dragons.",
                                  biome: .blossomOrchard, metersFromWorldStart: 200_000,
                                  relic: relic("ak-rose", "Everbloom Rose", "It has never wilted.", "cherry")),
                    TeamWorldZone(id: "ak-bridge", name: "Moat Bridge", tagline: "Swans glide under the arches.",
                                  biome: .riverside, metersFromWorldStart: 450_000,
                                  relic: relic("ak-box", "Royal Music Box", "Plays the kingdom's anthem.", "music-box")),
                    TeamWorldZone(id: "ak-castle", name: "Sleeping Castle", tagline: "The castle wakes as you arrive.",
                                  biome: .village, metersFromWorldStart: 800_000,
                                  relic: relic("ak-key", "Castle Key", "Opens every door in the kingdom.", "spyglass")),
                  ],
                  challenge: WorldChallenge(name: "Wake the Kingdom",
                                            detail: "Walk 100 km together in one week to ring the castle bells.", weekMeters: 100_000)),
    ]

    public static func world(withID id: String) -> TeamWorld? { worlds.first { $0.id == id } }

    /// Team distance at which `world` opens: after the unlock expedition, then
    /// each world follows the previous one.
    public static func startMeters(of world: TeamWorld) -> Int {
        let unlock = ExpeditionCatalog.all.prefix { $0.id != unlockExpeditionID }.reduce(0) { $0 + $1.goalMeters }
            + (ExpeditionCatalog.all.first { $0.id == unlockExpeditionID }?.goalMeters ?? 0)
        var start = unlock
        for candidate in worlds {
            if candidate.id == world.id { return start }
            start += candidate.lengthMeters
        }
        return start
    }
}

/// Where a team stands across all team worlds. Derived from the team's
/// lifetime distance in the ledger, so it's the same for every member and
/// never goes backwards.
public struct TeamWorldProgress: Hashable, Sendable {
    public let teamMeters: Int

    public init(teamMeters: Int) {
        self.teamMeters = max(0, teamMeters)
    }

    public var isUnlocked: Bool {
        guard let first = TeamWorldCatalog.worlds.first else { return false }
        return teamMeters >= TeamWorldCatalog.startMeters(of: first)
    }

    /// Distance still needed before the first world opens.
    public var metersToUnlock: Int {
        guard let first = TeamWorldCatalog.worlds.first else { return 0 }
        return max(0, TeamWorldCatalog.startMeters(of: first) - teamMeters)
    }

    /// The world the team is in now (the last one once everything is explored).
    public var currentWorld: TeamWorld? {
        guard isUnlocked else { return nil }
        return TeamWorldCatalog.worlds.last { teamMeters >= TeamWorldCatalog.startMeters(of: $0) }
    }

    /// Team distance walked inside `world`.
    public func meters(in world: TeamWorld) -> Int {
        max(0, min(world.lengthMeters, teamMeters - TeamWorldCatalog.startMeters(of: world)))
    }

    public func reachedZones(in world: TeamWorld) -> [TeamWorldZone] {
        guard teamMeters >= TeamWorldCatalog.startMeters(of: world) else { return [] }
        let walked = meters(in: world)
        return world.zones.filter { walked >= $0.metersFromWorldStart }
    }

    public func nextZone(in world: TeamWorld) -> TeamWorldZone? {
        let walked = meters(in: world)
        return world.zones.first { walked < $0.metersFromWorldStart }
    }

    /// All zones reached in every world so far.
    public var reachedZones: [TeamWorldZone] { TeamWorldCatalog.worlds.flatMap { reachedZones(in: $0) } }

    /// True when the team stands in the final zone of `world` (its challenge is open).
    public func challengeOpen(in world: TeamWorld) -> Bool {
        guard let last = world.zones.last else { return false }
        return reachedZones(in: world).contains(last)
    }
}

extension JournalEvents {
    public static func teamWorldZone(_ zone: TeamWorldZone, world: TeamWorld, teamName: String, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "teamworld-zone-\(zone.id)", kind: .expedition, day: day,
                     title: "\(teamName) reached \(zone.name)",
                     detail: "\(world.name): \(zone.tagline) Found the \(zone.relic.name).", iconID: zone.relic.spriteID)
    }

    public static func teamWorldChallenge(_ world: TeamWorld, teamName: String, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "teamworld-final-\(world.id)", kind: .expedition, day: day,
                     title: "\(teamName): \(world.challenge.name)!",
                     detail: "Together you completed \(world.name).", iconID: "medal")
    }
}
