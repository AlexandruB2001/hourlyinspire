import Foundation

/// One remembered moment of the journey.
public struct JournalEntry: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case distance, zone, relic, achievement, companion, referral, team, expedition, level, quest, wildlife, treasure, postcard
    }

    /// Stable key for the event (e.g. "zone-meadow"), so it is only ever recorded once.
    public let id: String
    public let kind: Kind
    public let day: LocalDay
    public let title: String
    public let detail: String
    /// Item sprite, or a companion/zone reference the UI knows how to draw.
    public let iconID: String

    public init(id: String, kind: Kind, day: LocalDay, title: String, detail: String, iconID: String) {
        self.id = id
        self.kind = kind
        self.day = day
        self.title = title
        self.detail = detail
        self.iconID = iconID
    }
}

/// A permanent log of milestones. Entries are never removed or rewritten.
public struct JourneyJournal: Codable, Hashable, Sendable {
    public private(set) var entries: [JournalEntry]

    public init(entries: [JournalEntry] = []) {
        self.entries = []
        record(entries)
    }

    /// Newest first.
    public var timeline: [JournalEntry] {
        entries.enumerated().sorted { lhs, rhs in
            lhs.element.day != rhs.element.day ? lhs.element.day > rhs.element.day : lhs.offset > rhs.offset
        }.map(\.element)
    }

    public func contains(_ id: String) -> Bool { entries.contains { $0.id == id } }

    /// This journal plus any entries only `other` has (a cloud save).
    public func merged(with other: JourneyJournal) -> JourneyJournal {
        var result = self
        result.record(other.entries)
        return result
    }

    /// Adds entries whose id isn't recorded yet. Returns the ones added.
    @discardableResult
    public mutating func record(_ new: [JournalEntry]) -> [JournalEntry] {
        var added: [JournalEntry] = []
        var seen = Set(entries.map(\.id))
        for entry in new where seen.insert(entry.id).inserted {
            entries.append(entry)
            added.append(entry)
        }
        return added
    }
}

/// Turns game state into journal entries. Pure: the same state always yields
/// the same ids, which is what makes recording idempotent.
public enum JournalEvents {
    /// Daily distances worth remembering.
    public static let dayMilestones = [5_000, 10_000, 15_000, 20_000]
    /// Lifetime distances worth remembering.
    public static let lifetimeMilestones = [10_000, 25_000, 42_195, 50_000, 100_000, 250_000, 500_000, 1_000_000]

    public static func entries(progression: ProgressionState, catalog: ZoneCatalog = .standard,
                               achievements: [Achievement] = AchievementCatalog.standard,
                               today: LocalDay) -> [JournalEntry] {
        var result: [JournalEntry] = []

        for zone in catalog.zones where progression.discoveredZoneIDs.contains(zone.id) && zone.startMeters > 0 {
            result.append(JournalEntry(id: "zone-\(zone.id)", kind: .zone, day: today,
                                       title: "Reached \(zone.name)", detail: zone.tagline, iconID: "zone:\(zone.biome.rawValue)"))
        }
        for item in catalog.allCollectibles where progression.collectedItemIDs.contains(item.id) {
            result.append(JournalEntry(id: "relic-\(item.id)", kind: .relic, day: today,
                                       title: "Found the \(item.name)", detail: item.detail, iconID: item.spriteID))
        }
        for achievement in achievements where achievement.isUnlocked(by: progression) {
            result.append(JournalEntry(id: "achievement-\(achievement.id)", kind: .achievement, day: today,
                                       title: achievement.name, detail: achievement.detail, iconID: achievement.spriteID))
        }
        for (key, meters) in progression.dailyBestMeters {
            guard let day = LocalDay(isoString: key) else { continue }
            for milestone in dayMilestones where meters >= milestone {
                result.append(JournalEntry(id: "day-\(milestone)-\(key)", kind: .distance, day: day,
                                           title: "Walked \(DistanceFormatting.kilometres(milestone)) in a day",
                                           detail: "A big day on the trail: \(DistanceFormatting.kilometres(meters)) in total.",
                                           iconID: milestone >= 20_000 ? "medal" : "boot"))
            }
        }
        for milestone in lifetimeMilestones where progression.lifetimeMeters >= milestone {
            result.append(JournalEntry(id: "lifetime-\(milestone)", kind: .distance, day: today,
                                       title: "\(DistanceFormatting.kilometres(milestone)) walked in total",
                                       detail: "Every step since your journey began.", iconID: "compass"))
        }
        return result
    }

    public static func evolution(_ stage: CompanionGrowth.Stage, of companion: CompanionState, on day: LocalDay) -> JournalEntry {
        let name = companion.species?.name ?? "Your companion"
        let detail = stage == .elder
            ? "\(name) glows with everything you've walked together."
            : "\(name) grew after \(stage.startKilometres) km together."
        return JournalEntry(id: "companion-\(companion.speciesID)-\(companion.adoptedOn.isoString)-\(stage.rawValue)",
                            kind: .companion, day: day, title: "\(name) became a \(stage.name)", detail: detail,
                            iconID: "companion:\(companion.speciesID):\(stage.rawValue)")
    }

    public static func adoption(of companion: CompanionState) -> JournalEntry {
        let name = companion.species?.name ?? "A companion"
        return JournalEntry(id: "companion-\(companion.speciesID)-\(companion.adoptedOn.isoString)-adopted",
                            kind: .companion, day: companion.adoptedOn, title: "\(name) joined you",
                            detail: companion.species?.tagline ?? "A new friend for the trail.",
                            iconID: "companion:\(companion.speciesID):0")
    }

    public static func referralChest(id: String, coins: Int, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "referral-\(id)", kind: .referral, day: day, title: "Opened a referral chest",
                     detail: "A friend you invited is walking too. +\(coins) coins.", iconID: "referral-chest")
    }
}
