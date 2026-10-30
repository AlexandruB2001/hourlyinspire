import Foundation

/// A kind of companion. Starters are free; the catalog is data so more
/// species (or cosmetic variants) can be added without touching growth logic.
public struct CompanionSpecies: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tagline: String
    public let personality: String
    /// What changes as it grows, in the companion's own terms.
    public let growthHint: String

    public init(id: String, name: String, tagline: String, personality: String, growthHint: String) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.personality = personality
        self.growthHint = growthHint
    }
}

public enum CompanionCatalog {
    public static let starters: [CompanionSpecies] = [
        CompanionSpecies(id: "mossling", name: "Mossling", tagline: "A pebble-sized stone golem.",
                         personality: "Patient and steady. Mossling never hurries, and never stops.",
                         growthHint: "Moss creeps over its stones and old runes begin to glow."),
        CompanionSpecies(id: "emberfox", name: "Emberfox", tagline: "A tiny fox with a warm glow.",
                         personality: "Curious and bouncy. Emberfox wants to see what's over every hill.",
                         growthHint: "Its tail catches light and its ears flicker with embers."),
        CompanionSpecies(id: "moonmoth", name: "Moonmoth", tagline: "A shy moth with moonlit wings.",
                         personality: "Dreamy and gentle. Moonmoth loves dusk and quiet trails.",
                         growthHint: "Its wings widen and fill with silvery moon-dust."),
    ]

    public static func species(withID id: String) -> CompanionSpecies? { starters.first { $0.id == id } }
}

/// How grown a companion is. Every kilometre walked together adds a small
/// detail; bigger changes come at the stage thresholds.
public struct CompanionGrowth: Hashable, Sendable {
    public enum Stage: Int, CaseIterable, Comparable, Sendable {
        case hatchling, sprout, companion, guardian, elder

        public var name: String {
            switch self {
            case .hatchling: return "Hatchling"
            case .sprout: return "Sprout"
            case .companion: return "Companion"
            case .guardian: return "Guardian"
            case .elder: return "Elder"
            }
        }

        /// Kilometres walked together to reach this stage.
        public var startKilometres: Int {
            switch self {
            case .hatchling: return 0
            case .sprout: return 5
            case .companion: return 20
            case .guardian: return 50
            case .elder: return 100
            }
        }

        public var next: Stage? { Stage(rawValue: rawValue + 1) }

        public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

        public static func stage(forKilometres km: Int) -> Stage {
            allCases.last { km >= $0.startKilometres } ?? .hatchling
        }
    }

    public let kilometres: Int
    public let stage: Stage

    public init(kilometres: Int) {
        self.kilometres = max(0, kilometres)
        stage = Stage.stage(forKilometres: self.kilometres)
    }

    /// Kilometres into the current stage: one new detail appears per kilometre.
    public var kilometresIntoStage: Int { kilometres - stage.startKilometres }

    /// Kilometres left until the next stage, or nil at the final stage.
    public var kilometresToNextStage: Int? { stage.next.map { $0.startKilometres - kilometres } }

    /// 0...1 progress toward the next stage (1 at the final stage).
    public var fractionToNextStage: Double {
        guard let next = stage.next else { return 1 }
        let span = next.startKilometres - stage.startKilometres
        return Double(kilometresIntoStage) / Double(span)
    }
}

/// The player's companion. Growth counts real walking since adoption, so a
/// new companion always starts small even for long-time walkers.
public struct CompanionState: Codable, Hashable, Sendable {
    public let speciesID: String
    public let adoptedOn: LocalDay
    /// Lifetime metres already walked when adopted.
    public let baselineMeters: Int
    /// Highest stage already celebrated (so evolutions are recorded once).
    public private(set) var celebratedStage: Int
    /// Worn accessory id per `CompanionAccessory.Slot`.
    public private(set) var accessories: [String: String]

    public init(speciesID: String, adoptedOn: LocalDay, lifetimeMeters: Int) {
        self.speciesID = speciesID
        self.adoptedOn = adoptedOn
        baselineMeters = max(0, lifetimeMeters)
        celebratedStage = CompanionGrowth.Stage.hatchling.rawValue
        accessories = [:]
    }

    enum CodingKeys: String, CodingKey { case speciesID, adoptedOn, baselineMeters, celebratedStage, accessories }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speciesID = try container.decode(String.self, forKey: .speciesID)
        adoptedOn = try container.decode(LocalDay.self, forKey: .adoptedOn)
        baselineMeters = try container.decode(Int.self, forKey: .baselineMeters)
        celebratedStage = try container.decode(Int.self, forKey: .celebratedStage)
        accessories = try container.decodeIfPresent([String: String].self, forKey: .accessories) ?? [:]
    }

    /// Accessory ids in draw order (back, neck, head).
    public var wornAccessories: [String] {
        [CompanionAccessory.Slot.back, .neck, .head].compactMap { accessories[$0.rawValue] }
    }

    /// Wears `accessory`, or takes it off if it's already worn.
    public mutating func toggle(_ accessory: CompanionAccessory) {
        if accessories[accessory.slot.rawValue] == accessory.id {
            accessories[accessory.slot.rawValue] = nil
        } else {
            accessories[accessory.slot.rawValue] = accessory.id
        }
    }

    public var species: CompanionSpecies? { CompanionCatalog.species(withID: speciesID) }

    public func growth(lifetimeMeters: Int) -> CompanionGrowth {
        CompanionGrowth(kilometres: max(0, lifetimeMeters - baselineMeters) / 1_000)
    }

    /// Picks between two devices' companions (a cloud save): the one adopted
    /// first is the real one; for the same companion, the highest celebrated stage.
    public func merged(with other: CompanionState) -> CompanionState {
        guard other.speciesID == speciesID, other.adoptedOn == adoptedOn else {
            return other.adoptedOn < adoptedOn ? other : self
        }
        var result = self
        result.celebratedStage = max(celebratedStage, other.celebratedStage)
        if accessories.isEmpty { result.accessories = other.accessories }
        return result
    }

    /// Stages reached since the last call, oldest first. Each is returned once.
    public mutating func newEvolutions(lifetimeMeters: Int) -> [CompanionGrowth.Stage] {
        let stage = growth(lifetimeMeters: lifetimeMeters).stage
        guard stage.rawValue > celebratedStage else { return [] }
        let reached = CompanionGrowth.Stage.allCases.filter { $0.rawValue > celebratedStage && $0 <= stage }
        celebratedStage = stage.rawValue
        return reached
    }
}
