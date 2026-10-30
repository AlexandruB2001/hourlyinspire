import Foundation

/// What unlocks titles and frames. Built from permanent progress, so an
/// unlock never goes away.
public struct ProfileFacts: Hashable, Sendable {
    public var progression: ProgressionState
    public var explorerLevel: Int
    public var ledger: RewardLedger
    public var journal: JourneyJournal
    /// Highest companion stage ever reached (raw value), if any.
    public var companionStage: Int?
    public var collections: CollectionState

    public init(progression: ProgressionState, explorerLevel: Int, ledger: RewardLedger, journal: JourneyJournal,
                companionStage: Int?, collections: CollectionState = CollectionState()) {
        self.progression = progression
        self.explorerLevel = explorerLevel
        self.ledger = ledger
        self.journal = journal
        self.companionStage = companionStage
        self.collections = collections
    }

    var questsClaimed: Int {
        ledger.claimed.keys.filter { $0.hasPrefix("quest-") && !$0.hasPrefix("quest-week-chest-") }.count
    }

    var weeklyChests: Int { ledger.claimed.keys.filter { $0.hasPrefix("quest-week-chest-") }.count }
    var expeditions: Int { journal.entries.filter { $0.kind == .expedition }.count }
}

public enum UnlockRequirement: Hashable, Sendable {
    case always
    case achievement(String)
    case explorerLevel(Int)
    case zonesDiscovered([String])
    case relics(Int)
    case activeDays(Int)
    case questsClaimed(Int)
    case weeklyChests(Int)
    case companionStage(CompanionGrowth.Stage)
    case expeditions(Int)
    case creatures(Int)
    case treasures(Int)
    /// Every tier of a seasonal event, in any year.
    case eventCompleted(String)

    public func isMet(by facts: ProfileFacts) -> Bool {
        switch self {
        case .always: return true
        case .achievement(let id):
            return AchievementCatalog.standard.first { $0.id == id }?.isUnlocked(by: facts.progression) ?? false
        case .explorerLevel(let level): return facts.explorerLevel >= level
        case .zonesDiscovered(let ids): return Set(ids).isSubset(of: facts.progression.discoveredZoneIDs)
        case .relics(let count): return facts.progression.collectedItemIDs.count >= count
        case .activeDays(let count): return facts.progression.activeDays() >= count
        case .questsClaimed(let count): return facts.questsClaimed >= count
        case .weeklyChests(let count): return facts.weeklyChests >= count
        case .companionStage(let stage): return (facts.companionStage ?? -1) >= stage.rawValue
        case .expeditions(let count): return facts.expeditions >= count
        case .creatures(let count): return facts.collections.wildlife.count >= count
        case .treasures(let count): return facts.collections.treasures.count >= count
        case .eventCompleted(let id):
            guard let event = SeasonalEventCatalog.event(withID: id) else { return false }
            let suffix = "-tier-\(event.tiers.count)"
            return facts.ledger.claimed.keys.contains { $0.hasPrefix("event-\(id)-") && $0.hasSuffix(suffix) }
        }
    }

    /// How to unlock it, for locked entries.
    public var hint: String {
        switch self {
        case .always: return "Yours from the start."
        case .achievement(let id):
            return "Unlock the \(AchievementCatalog.standard.first { $0.id == id }?.name ?? id) achievement."
        case .explorerLevel(let level): return "Reach Explorer Level \(level)."
        case .zonesDiscovered(let ids):
            let names = ids.compactMap { id in ZoneCatalog.standard.zones.first { $0.id == id }?.name }
            return "Discover \(names.joined(separator: " and "))."
        case .relics(let count): return "Find \(count) relics."
        case .activeDays(let count): return "Walk at least 1 km on \(count) different days."
        case .questsClaimed(let count): return "Complete \(count) quests."
        case .weeklyChests(let count): return count == 1 ? "Open a weekly quest chest." : "Open \(count) weekly quest chests."
        case .companionStage(let stage): return "Grow your companion to a \(stage.name)."
        case .expeditions(let count): return count == 1 ? "Complete a team expedition." : "Complete \(count) team expeditions."
        case .creatures(let count): return "Spot \(count) different creatures."
        case .treasures(let count): return "Find \(count) treasures."
        case .eventCompleted(let id):
            return "Finish every tier of \(SeasonalEventCatalog.event(withID: id)?.name ?? "a seasonal event")."
        }
    }
}

/// A title shown under your username.
public struct PlayerTitle: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let requirement: UnlockRequirement

    public init(id: String, name: String, requirement: UnlockRequirement) {
        self.id = id
        self.name = name
        self.requirement = requirement
    }
}

public enum TitleCatalog {
    public static let defaultID = "wanderer"

    public static let all: [PlayerTitle] = [
        PlayerTitle(id: "wanderer", name: "The Wanderer", requirement: .always),
        PlayerTitle(id: "first-steps", name: "First Stepper", requirement: .achievement("first-steps")),
        PlayerTitle(id: "trailblazer", name: "Trailblazer", requirement: .achievement("trailblazer")),
        PlayerTitle(id: "summiteer", name: "Summiteer", requirement: .achievement("summiteer")),
        PlayerTitle(id: "lighthouse-keeper", name: "Lighthouse Keeper", requirement: .achievement("lightkeeper")),
        PlayerTitle(id: "off-the-map", name: "Off the Map", requirement: .achievement("off-the-map")),
        PlayerTitle(id: "forest-guardian", name: "Forest Guardian", requirement: .zonesDiscovered(["pine-forest", "cloud-forest", "maple-woods"])),
        PlayerTitle(id: "marathoner", name: "Marathoner", requirement: .achievement("marathoner")),
        PlayerTitle(id: "collector", name: "The Collector", requirement: .relics(10)),
        PlayerTitle(id: "curator", name: "Grand Curator", requirement: .relics(20)),
        PlayerTitle(id: "rambler", name: "Regular Rambler", requirement: .activeDays(7)),
        PlayerTitle(id: "eternal-rambler", name: "Eternal Rambler", requirement: .activeDays(100)),
        PlayerTitle(id: "questkeeper", name: "Questkeeper", requirement: .questsClaimed(20)),
        PlayerTitle(id: "weekly-champion", name: "Weekly Champion", requirement: .weeklyChests(1)),
        PlayerTitle(id: "companions-friend", name: "Companion's Friend", requirement: .companionStage(.companion)),
        PlayerTitle(id: "elder-keeper", name: "Elder Keeper", requirement: .companionStage(.elder)),
        PlayerTitle(id: "team-spirit", name: "Team Spirit", requirement: .expeditions(1)),
        PlayerTitle(id: "wildlife-watcher", name: "Wildlife Watcher", requirement: .creatures(10)),
        PlayerTitle(id: "naturalist", name: "Naturalist", requirement: .creatures(WildlifeCatalog.all.count)),
        PlayerTitle(id: "treasure-hunter", name: "Treasure Hunter", requirement: .treasures(4)),
        PlayerTitle(id: "harvest-keeper", name: "Harvest Keeper", requirement: .eventCompleted("great-harvest")),
        PlayerTitle(id: "winter-wanderer", name: "Winter Wanderer", requirement: .eventCompleted("winter-wanderer")),
        PlayerTitle(id: "bloom-bringer", name: "Bloom Bringer", requirement: .eventCompleted("spring-awakening")),
        PlayerTitle(id: "ocean-voyager", name: "Ocean Voyager", requirement: .eventCompleted("ocean-expedition")),
        PlayerTitle(id: "star-catcher", name: "Star Catcher", requirement: .eventCompleted("starfall-festival")),
        PlayerTitle(id: "seasoned-explorer", name: "Seasoned Explorer", requirement: .explorerLevel(10)),
        PlayerTitle(id: "master-explorer", name: "Master Explorer", requirement: .explorerLevel(20)),
        PlayerTitle(id: "legendary-explorer", name: "Legendary Explorer", requirement: .explorerLevel(40)),
    ]

    public static func title(withID id: String?) -> PlayerTitle? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

/// The border drawn around your walker on your profile and friend cards.
public struct ProfileFrame: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// 0xRRGGBB colours: outer border, inner highlight.
    public let outer: UInt32
    public let inner: UInt32
    public let requirement: UnlockRequirement

    public init(id: String, name: String, outer: UInt32, inner: UInt32, requirement: UnlockRequirement) {
        self.id = id
        self.name = name
        self.outer = outer
        self.inner = inner
        self.requirement = requirement
    }
}

public enum FrameCatalog {
    public static let defaultID = "oak"

    public static let all: [ProfileFrame] = [
        ProfileFrame(id: "oak", name: "Oak", outer: 0x5B3A22, inner: 0x8A5A36, requirement: .always),
        ProfileFrame(id: "copper", name: "Copper", outer: 0x8C4A2F, inner: 0xD9895B, requirement: .explorerLevel(5)),
        ProfileFrame(id: "moss", name: "Moss", outer: 0x2F5A2E, inner: 0x7CB86A, requirement: .companionStage(.sprout)),
        ProfileFrame(id: "silver", name: "Silver", outer: 0x6E7B86, inner: 0xD8E1E8, requirement: .explorerLevel(10)),
        ProfileFrame(id: "ocean", name: "Ocean", outer: 0x1F4E79, inner: 0x6FC3E8, requirement: .zonesDiscovered(["lighthouse-point"])),
        ProfileFrame(id: "gold", name: "Gold", outer: 0x9A6B12, inner: 0xF2C94C, requirement: .explorerLevel(20)),
        ProfileFrame(id: "crystal", name: "Crystal", outer: 0x4B3C8C, inner: 0xB9A6F2, requirement: .explorerLevel(30)),
        ProfileFrame(id: "aurora", name: "Aurora", outer: 0x1E6B5C, inner: 0x8CF2C9, requirement: .explorerLevel(40)),
    ]

    public static func frame(withID id: String?) -> ProfileFrame {
        all.first { $0.id == id } ?? all[0]
    }
}

/// The player's chosen profile look. Everything is optional; unset or no
/// longer valid choices fall back to the defaults.
public struct ProfileShowcase: Codable, Hashable, Sendable {
    public var titleID: String
    public var frameID: String
    public var favoriteZoneID: String?
    /// Up to three achievements to show off.
    public var achievementIDs: [String]
    public var showsCompanion: Bool

    public static let maxAchievements = 3

    public init(titleID: String = TitleCatalog.defaultID, frameID: String = FrameCatalog.defaultID,
                favoriteZoneID: String? = nil, achievementIDs: [String] = [], showsCompanion: Bool = true) {
        self.titleID = titleID
        self.frameID = frameID
        self.favoriteZoneID = favoriteZoneID
        self.achievementIDs = Array(achievementIDs.prefix(Self.maxAchievements))
        self.showsCompanion = showsCompanion
    }

    enum CodingKeys: String, CodingKey { case titleID, frameID, favoriteZoneID, achievementIDs, showsCompanion }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(titleID: try container.decodeIfPresent(String.self, forKey: .titleID) ?? TitleCatalog.defaultID,
                  frameID: try container.decodeIfPresent(String.self, forKey: .frameID) ?? FrameCatalog.defaultID,
                  favoriteZoneID: try container.decodeIfPresent(String.self, forKey: .favoriteZoneID),
                  achievementIDs: try container.decodeIfPresent([String].self, forKey: .achievementIDs) ?? [],
                  showsCompanion: try container.decodeIfPresent(Bool.self, forKey: .showsCompanion) ?? true)
    }

    /// Drops anything that isn't unlocked (e.g. after restoring an older save).
    public func validated(with facts: ProfileFacts) -> ProfileShowcase {
        var result = self
        if TitleCatalog.title(withID: titleID).map({ !$0.requirement.isMet(by: facts) }) ?? true {
            result.titleID = TitleCatalog.defaultID
        }
        if !FrameCatalog.frame(withID: frameID).requirement.isMet(by: facts) || FrameCatalog.frame(withID: frameID).id != frameID {
            result.frameID = FrameCatalog.defaultID
        }
        if let zone = favoriteZoneID, !facts.progression.discoveredZoneIDs.contains(zone) { result.favoriteZoneID = nil }
        let unlocked = Set(AchievementCatalog.standard.filter { $0.isUnlocked(by: facts.progression) }.map(\.id))
        result.achievementIDs = achievementIDs.filter(unlocked.contains)
        return result
    }

    public mutating func toggleAchievement(_ id: String) {
        if let index = achievementIDs.firstIndex(of: id) {
            achievementIDs.remove(at: index)
        } else if achievementIDs.count < Self.maxAchievements {
            achievementIDs.append(id)
        }
    }
}

/// What friends and teammates see of someone's showcase.
public struct PublicShowcase: Hashable, Sendable {
    public let userID: UserID
    public let titleID: String?
    public let frameID: String?
    public let favoriteZoneID: String?

    public init(userID: UserID, titleID: String?, frameID: String?, favoriteZoneID: String?) {
        self.userID = userID
        self.titleID = titleID
        self.frameID = frameID
        self.favoriteZoneID = favoriteZoneID
    }

    /// The title's display name, or nil for unknown ids (e.g. from a newer app).
    public var titleName: String? { TitleCatalog.title(withID: titleID)?.name }
}
