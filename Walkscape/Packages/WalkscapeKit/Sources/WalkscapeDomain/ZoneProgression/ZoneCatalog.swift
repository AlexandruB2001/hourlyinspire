import Foundation

/// Data-driven list of zones. Zones must be contiguous and start at 0 m.
/// Distances past the last zone continue into generated "beyond" zones so
/// any distance maps to a zone without crashing.
public struct ZoneCatalog: Codable, Hashable, Sendable {
    public enum ValidationError: Error, Equatable {
        case empty
        case doesNotStartAtZero
        case gap(afterZoneID: String)
        case nonPositiveLength(zoneID: String)
        case duplicateID(String)
        case invalidBeyondConfiguration
    }

    public let zones: [Zone]
    /// Biomes cycled through for generated zones after the last defined zone.
    public let beyondBiomes: [Biome]
    public let beyondLengthMeters: Int

    public init(zones: [Zone], beyondBiomes: [Biome] = Biome.allCases, beyondLengthMeters: Int = 1_000) throws {
        guard let first = zones.first else { throw ValidationError.empty }
        guard first.startMeters == 0 else { throw ValidationError.doesNotStartAtZero }
        guard !beyondBiomes.isEmpty, beyondLengthMeters > 0 else { throw ValidationError.invalidBeyondConfiguration }
        var seen = Set<String>()
        for (index, zone) in zones.enumerated() {
            guard zone.lengthMeters > 0 else { throw ValidationError.nonPositiveLength(zoneID: zone.id) }
            guard seen.insert(zone.id).inserted else { throw ValidationError.duplicateID(zone.id) }
            if index > 0, zones[index - 1].endMeters != zone.startMeters {
                throw ValidationError.gap(afterZoneID: zones[index - 1].id)
            }
        }
        self.zones = zones
        self.beyondBiomes = beyondBiomes
        self.beyondLengthMeters = beyondLengthMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(zones: try container.decode([Zone].self, forKey: .zones),
                      beyondBiomes: try container.decodeIfPresent([Biome].self, forKey: .beyondBiomes) ?? Biome.allCases,
                      beyondLengthMeters: try container.decodeIfPresent(Int.self, forKey: .beyondLengthMeters) ?? 1_000)
    }

    /// Metres at which the defined zones end.
    public var definedEndMeters: Int { zones.last!.endMeters }

    /// Index of the zone containing `meters`. Negative distances clamp to 0.
    public func zoneIndex(forMeters meters: Int) -> Int {
        let meters = max(0, meters)
        if meters >= definedEndMeters {
            return zones.count + (meters - definedEndMeters) / beyondLengthMeters
        }
        // Binary search for the last zone whose start <= meters.
        var low = 0
        var high = zones.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if zones[mid].startMeters <= meters { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The zone at `index`, generating "beyond" zones past the defined list.
    public func zone(at index: Int) -> Zone {
        let index = max(0, index)
        if index < zones.count { return zones[index] }
        let beyond = index - zones.count
        let start = definedEndMeters + beyond * beyondLengthMeters
        let biome = beyondBiomes[beyond % beyondBiomes.count]
        return Zone(id: "beyond-\(beyond + 1)",
                    name: "Wanderer's Road \(beyond + 1)",
                    tagline: "Past the summit, the road keeps going.",
                    detail: "Uncharted country for walkers who never stop. Every extra kilometre adds a new stretch.",
                    biome: biome,
                    startMeters: start,
                    endMeters: start + beyondLengthMeters)
    }

    public func zone(forMeters meters: Int) -> Zone { zone(at: zoneIndex(forMeters: meters)) }

    public func zone(withID id: String) -> Zone? {
        if let zone = zones.first(where: { $0.id == id }) { return zone }
        guard id.hasPrefix("beyond-"), let number = Int(id.dropFirst("beyond-".count)), number >= 1 else { return nil }
        return zone(at: zones.count + number - 1)
    }

    public var allCollectibles: [Collectible] { zones.compactMap(\.discovery) }
}

public extension ZoneCatalog {
    /// The launch journey: ten 1 km zones from Meadow to Summit.
    static let standard: ZoneCatalog = {
        func km(_ index: Int) -> (Int, Int) { (index * 1_000, (index + 1) * 1_000) }
        let entries: [(String, String, String, String, Biome, Collectible)] = [
            ("meadow", "Sunny Meadow", "Wildflowers sway where every journey begins.",
             "Soft grass, humming bees and a dirt path that wanders off toward the river.", .meadow,
             Collectible(id: "clover", name: "Four-leaf Clover", detail: "Found among the wildflowers. Lucky!", spriteID: "clover")),
            ("riverside", "Riverside", "A lazy river and a creaky wooden bridge.",
             "The water chatters over smooth stones. Someone left a fishing rod by the bridge.", .riverside,
             Collectible(id: "river-stone", name: "River Stone", detail: "Worn perfectly smooth by the current.", spriteID: "stone")),
            ("pine-forest", "Pine Forest", "Tall pines hum with birdsong.",
             "Needles crunch underfoot and sunlight falls in thin golden beams.", .pineForest,
             Collectible(id: "pinecone", name: "Golden Pinecone", detail: "It still smells like the forest.", spriteID: "pinecone")),
            ("rolling-hills", "Rolling Hills", "Soft green hills roll toward the horizon.",
             "Sheep graze between stone walls, and the wind carries kites high overhead.", .rollingHills,
             Collectible(id: "feather", name: "Kite Feather", detail: "Snagged from a passing breeze.", spriteID: "feather")),
            ("lakeside", "Lakeside", "A mirror-still lake reflects the clouds.",
             "Reeds whisper at the shore and the far mountains float upside down in the water.", .lakeside,
             Collectible(id: "shell", name: "Spiral Shell", detail: "Hold it to your ear for lake sounds.", spriteID: "shell")),
            ("village", "Hearth Village", "Chimney smoke and warm bread.",
             "Cottages lean together around a cobbled lane. The baker waves as you pass.", .village,
             Collectible(id: "lantern", name: "Brass Lantern", detail: "A gift from the village lamplighter.", spriteID: "lantern")),
            ("crystal-caves", "Crystal Caves", "Glowing crystals light the way.",
             "Cool air, dripping echoes and crystals that pulse softly in the dark.", .crystalCaves,
             Collectible(id: "crystal", name: "Glow Crystal", detail: "It glows a little brighter when you walk.", spriteID: "crystal")),
            ("snowy-ridge", "Snowy Ridge", "Crisp air and fresh snow underfoot.",
             "Snow-dusted pines line a narrow ridge. Your breath curls into little clouds.", .snowyRidge,
             Collectible(id: "snowflake", name: "Snowflake Charm", detail: "It never melts.", spriteID: "snowflake")),
            ("cloud-forest", "Cloud Forest", "Mist drifts between mossy giants.",
             "Ancient trees wear coats of moss, and glowing mushrooms dot the trail.", .cloudForest,
             Collectible(id: "mushroom", name: "Glowcap Mushroom", detail: "Softly luminous. Do not eat.", spriteID: "mushroom")),
            ("summit", "The Summit", "The whole world, all at once.",
             "Above the clouds, the path you walked today stretches out below you.", .summit,
             Collectible(id: "summit-flag", name: "Summit Flag", detail: "Proof you made it all the way up.", spriteID: "flag")),
        ]
        let zones = entries.enumerated().map { index, entry in
            let (start, end) = km(index)
            return Zone(id: entry.0, name: entry.1, tagline: entry.2, detail: entry.3, biome: entry.4,
                        startMeters: start, endMeters: end, discovery: entry.5)
        }
        // The standard catalog is static data; a validation failure is a programmer error.
        return try! ZoneCatalog(zones: zones)
    }()
}
