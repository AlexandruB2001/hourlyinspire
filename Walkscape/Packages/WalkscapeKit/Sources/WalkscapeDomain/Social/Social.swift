import Foundation

// MARK: - Discoveries worth sharing

/// A special find on a day: a world event or a rare-or-better creature
/// sighting. Everyone gets the same events and sightings on the same day,
/// so two friends with the same discovery found it "together".
public struct DiscoveryRecord: Hashable, Sendable {
    public let id: String
    public let day: LocalDay

    public init(id: String, day: LocalDay) {
        self.id = id
        self.day = day
    }
}

public enum SharedDiscoveries {
    /// Today's special finds: events found and rare+ creatures sighted
    /// (whether or not they were new to the collection).
    public static func records(on day: LocalDay, zonesReached: [String], foundEvents: [ScheduledEvent]) -> [DiscoveryRecord] {
        let creatures = WildlifeCatalog.sightings(on: day, zonesReached: zonesReached)
            .filter { $0.rarity >= .rare }
            .map { DiscoveryRecord(id: $0.id, day: day) }
        return creatures + foundEvents.map { DiscoveryRecord(id: $0.event.id, day: $0.day) }
    }

    /// The display name of a discovery id.
    public static func name(of id: String) -> String {
        WildlifeCatalog.creature(withID: id)?.name ?? WorldEventCatalog.event(withID: id)?.name ?? id
    }

    public static func spriteID(of id: String) -> String {
        WildlifeCatalog.creature(withID: id)?.spriteID ?? WorldEventCatalog.event(withID: id)?.spriteID ?? "star"
    }
}

/// You and a friend found the same thing on the same day.
public struct SharedDiscovery: Identifiable, Hashable, Sendable {
    public let discoveryID: String
    public let day: LocalDay
    public let friendID: UserID
    public let friendName: String

    public init(discoveryID: String, day: LocalDay, friendID: UserID, friendName: String) {
        self.discoveryID = discoveryID
        self.day = day
        self.friendID = friendID
        self.friendName = friendName
    }

    public var id: String { "shared-\(discoveryID)-\(day.isoString)-\(friendID.rawValue)" }
    public var reward: Reward { Reward(id: id, coins: 25, xp: 60) }

    public var journalEntry: JournalEntry {
        JournalEntry(id: id, kind: .shared, day: day,
                     title: "You and @\(friendName) found the \(SharedDiscoveries.name(of: discoveryID))!",
                     detail: "The same discovery, on the same day. Walking apart, together.",
                     iconID: SharedDiscoveries.spriteID(of: discoveryID))
    }
}

// MARK: - Friend milestones

public enum FriendMilestoneCatalog {
    /// Milestone id → how friends read it ("@sam walked their first 10 km!").
    public static let phrases: [String: String] = [
        "total-10k": "walked their first 10 km!",
        "total-50k": "walked 50 km in total!",
        "total-100k": "walked 100 km in total!",
        "total-500k": "walked 500 km in total!",
        "day-10k": "walked 10 km in a single day!",
        "first-expedition": "finished their first team expedition!",
        "companion-sprout": "watched their companion become a Sprout!",
        "companion-companion": "watched their companion become a Companion!",
        "companion-guardian": "watched their companion become a Guardian!",
        "companion-elder": "watched their companion become an Elder!",
        "level-10": "reached Explorer Level 10!",
        "level-20": "reached Explorer Level 20!",
        "level-30": "reached Explorer Level 30!",
    ]

    public static func phrase(for id: String) -> String { phrases[id] ?? "reached a new milestone!" }

    /// Milestones to share, worked out from the Journal (each with the day it happened).
    public static func milestones(in journal: JourneyJournal) -> [DiscoveryRecord] {
        var result: [String: LocalDay] = [:]
        func note(_ id: String, _ day: LocalDay) {
            if let existing = result[id], existing <= day { return }
            result[id] = day
        }
        for entry in journal.entries {
            switch entry.kind {
            case .distance:
                if entry.id.hasPrefix("lifetime-") {
                    let meters = Int(entry.id.dropFirst("lifetime-".count)) ?? 0
                    if [10_000, 50_000, 100_000, 500_000].contains(meters) { note("total-\(meters / 1_000)k", entry.day) }
                } else if entry.id.hasPrefix("day-10000-") {
                    note("day-10k", entry.day)
                }
            case .expedition:
                note("first-expedition", entry.day)
            case .companion:
                for stage in CompanionGrowth.Stage.allCases where stage != .hatchling && entry.id.hasSuffix("-\(stage.rawValue)")
                    && entry.id.hasPrefix("companion-") && !entry.id.hasPrefix("companion-find-") {
                    note("companion-\(stage.name.lowercased())", entry.day)
                }
            case .level:
                if let level = Int(entry.id.dropFirst("level-".count)), level >= 10 {
                    for mark in [10, 20, 30] where level >= mark { note("level-\(mark)", entry.day) }
                }
            default:
                break
            }
        }
        return result.map { DiscoveryRecord(id: $0.key, day: $0.value) }.sorted { $0.id < $1.id }
    }
}

public enum Reaction: String, CaseIterable, Codable, Sendable {
    case cheer, clap, star, heart

    public var emoji: String {
        switch self {
        case .cheer: return "🎉"
        case .clap: return "👏"
        case .star: return "⭐"
        case .heart: return "💛"
        }
    }
}

/// A friend's milestone in the feed.
public struct FriendMilestone: Identifiable, Hashable, Sendable {
    public let friendID: UserID
    public let username: String
    public let avatarID: String
    public let milestoneID: String
    public let day: LocalDay
    public let reactions: Int
    public let myReaction: Reaction?

    public init(friendID: UserID, username: String, avatarID: String, milestoneID: String, day: LocalDay,
                reactions: Int, myReaction: Reaction?) {
        self.friendID = friendID
        self.username = username
        self.avatarID = avatarID
        self.milestoneID = milestoneID
        self.day = day
        self.reactions = reactions
        self.myReaction = myReaction
    }

    public var id: String { "\(friendID.rawValue)-\(milestoneID)" }
    public var text: String { "@\(username) \(FriendMilestoneCatalog.phrase(for: milestoneID))" }
}

/// 100 km (and more) walked with a friend, counted from when you became friends.
public enum WalkedTogether {
    public static let milestones = [100_000, 250_000, 500_000]

    public static func rewards(friendID: UserID, meters: Int) -> [Reward] {
        milestones.filter { meters >= $0 }.map {
            Reward(id: "together-\($0 / 1_000)k-\(friendID.rawValue)", coins: $0 / 2_000, xp: $0 / 500)
        }
    }

    public static func journalEntry(friendName: String, friendID: UserID, meters: Int, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "together-\(meters / 1_000)k-\(friendID.rawValue)", kind: .shared, day: day,
                     title: "\(meters / 1_000) km walked with @\(friendName)",
                     detail: "Every step you've both taken since becoming friends.", iconID: "compass")
    }
}
