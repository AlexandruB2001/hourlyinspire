import Foundation

/// A limited-time event that comes back every year on the same dates
/// (so nobody misses it forever). Add a new one by adding a definition to
/// `SeasonalEventCatalog`; everything else (quests, tiers, rewards,
/// community goal, Journal) is driven by this data.
public struct SeasonalEvent: Identifiable, Hashable, Sendable {
    public struct MonthDay: Hashable, Sendable {
        public let month: Int
        public let day: Int

        public init(_ month: Int, _ day: Int) {
            self.month = month
            self.day = day
        }
    }

    public struct Tier: Hashable, Sendable {
        /// Kilometres walked during the event.
        public let kilometres: Int
        public let coins: Int
        public let xp: Int
        /// Exclusive items given at this tier (companion accessories).
        public let itemIDs: [String]
    }

    public struct Quest: Identifiable, Hashable, Sendable {
        public enum Goal: Hashable, Sendable {
            case kilometres(Int)
            case activeDays(Int)
            case creatures(Int)
        }

        public let id: String
        public let title: String
        public let goal: Goal
        public let coins: Int
        public let xp: Int

        public var target: Int {
            switch goal {
            case .kilometres(let n), .activeDays(let n), .creatures(let n): return n
            }
        }
    }

    public let id: String
    public let name: String
    public let tagline: String
    public let start: MonthDay
    public let end: MonthDay
    public let season: Season
    public let spriteID: String
    public let tiers: [Tier]
    public let quests: [Quest]
    /// Everyone's combined distance during the event, in km.
    public let communityGoalKilometres: Int
    /// The title earned by finishing every tier.
    public let titleID: String
}

/// One year's run of an event.
public struct EventRun: Identifiable, Hashable, Sendable {
    public let event: SeasonalEvent
    public let startDay: LocalDay
    public let endDay: LocalDay

    /// Unique per event and year: rewards from one year never block the next.
    public var id: String { "\(event.id)-\(startDay.year)" }

    public func contains(_ day: LocalDay) -> Bool { day >= startDay && day <= endDay }

    public func daysLeft(from day: LocalDay) -> Int {
        var count = 0
        var cursor = day
        while cursor <= endDay {
            count += 1
            cursor = cursor.adding(days: 1)
        }
        return count
    }

    public func tierReward(_ index: Int) -> Reward {
        let tier = event.tiers[index]
        return Reward(id: "event-\(id)-tier-\(index + 1)", coins: tier.coins, xp: tier.xp, itemIDs: tier.itemIDs)
    }

    public func questReward(_ quest: SeasonalEvent.Quest) -> Reward {
        Reward(id: "event-\(id)-quest-\(quest.id)", coins: quest.coins, xp: quest.xp)
    }

    public var communityReward: Reward { Reward(id: "event-\(id)-community", coins: 75, xp: 200) }
    /// Walkers need this much of their own walking in the event for the community reward.
    public static let communityShareMeters = 5_000
}

/// How far a player is through one event run. All derived from the best
/// distance per day, so it can't double-count and can't go backwards.
public struct EventProgress: Hashable, Sendable {
    public let run: EventRun
    /// Event walking, capped at 10 km a day so it never asks for huge days.
    public let meters: Int
    public let activeDays: Int
    public let creatures: Int

    public static let dailyCapMeters = 10_000

    public init(run: EventRun, progression: ProgressionState, collections: CollectionState) {
        self.run = run
        var meters = 0
        var active = 0
        for (key, best) in progression.dailyBestMeters {
            guard let day = LocalDay(isoString: key), run.contains(day) else { continue }
            meters += min(best, Self.dailyCapMeters)
            if best >= 1_000 { active += 1 }
        }
        self.meters = meters
        activeDays = active
        creatures = collections.wildlife.values.filter(run.contains).count
    }

    public var kilometres: Int { meters / 1_000 }

    public var tiersReached: Int { run.event.tiers.filter { kilometres >= $0.kilometres }.count }

    public var nextTier: SeasonalEvent.Tier? { run.event.tiers.first { kilometres < $0.kilometres } }

    public func progress(of quest: SeasonalEvent.Quest) -> Int {
        let value: Int
        switch quest.goal {
        case .kilometres: value = kilometres
        case .activeDays: value = activeDays
        case .creatures: value = creatures
        }
        return min(quest.target, value)
    }

    /// Every reward unlocked so far (tiers and quests). Claiming goes through the ledger.
    public var unlockedRewards: [Reward] {
        let tiers = (0..<tiersReached).map(run.tierReward)
        let quests = run.event.quests.filter { progress(of: $0) >= $0.target }.map(run.questReward)
        return tiers + quests
    }
}

public enum SeasonalEventCatalog {
    public static let all: [SeasonalEvent] = [
        SeasonalEvent(
            id: "great-harvest", name: "Great Harvest", tagline: "Pumpkins, lanterns and golden fields.",
            start: .init(10, 15), end: .init(11, 12), season: .autumn, spriteID: "maple",
            tiers: [
                .init(kilometres: 5, coins: 30, xp: 100, itemIDs: []),
                .init(kilometres: 15, coins: 50, xp: 150, itemIDs: ["pet-pumpkin-hat"]),
                .init(kilometres: 30, coins: 80, xp: 250, itemIDs: []),
                .init(kilometres: 50, coins: 120, xp: 400, itemIDs: []),
            ],
            quests: [
                .init(id: "harvest-days", title: "Walk 1 km on 7 days of the Harvest", goal: .activeDays(7), coins: 40, xp: 120),
                .init(id: "harvest-critters", title: "Spot 3 creatures during the Harvest", goal: .creatures(3), coins: 30, xp: 100),
            ],
            communityGoalKilometres: 10_000, titleID: "harvest-keeper"),
        SeasonalEvent(
            id: "winter-wanderer", name: "Winter Wanderer", tagline: "Frosty trails and warm lanterns.",
            start: .init(12, 15), end: .init(1, 12), season: .winter, spriteID: "snowflake",
            tiers: [
                .init(kilometres: 5, coins: 30, xp: 100, itemIDs: []),
                .init(kilometres: 15, coins: 50, xp: 150, itemIDs: ["pet-snow-hat"]),
                .init(kilometres: 30, coins: 80, xp: 250, itemIDs: []),
                .init(kilometres: 50, coins: 120, xp: 400, itemIDs: []),
            ],
            quests: [
                .init(id: "winter-days", title: "Brave the cold on 7 days", goal: .activeDays(7), coins: 40, xp: 120),
                .init(id: "winter-km", title: "Walk 20 km of winter trails", goal: .kilometres(20), coins: 40, xp: 120),
            ],
            communityGoalKilometres: 12_000, titleID: "winter-wanderer"),
        SeasonalEvent(
            id: "spring-awakening", name: "Spring Awakening", tagline: "Everything blooms again.",
            start: .init(3, 20), end: .init(4, 17), season: .spring, spriteID: "cherry",
            tiers: [
                .init(kilometres: 5, coins: 30, xp: 100, itemIDs: []),
                .init(kilometres: 15, coins: 50, xp: 150, itemIDs: ["pet-petal-crown"]),
                .init(kilometres: 30, coins: 80, xp: 250, itemIDs: []),
                .init(kilometres: 50, coins: 120, xp: 400, itemIDs: []),
            ],
            quests: [
                .init(id: "spring-critters", title: "Spot 5 creatures waking up", goal: .creatures(5), coins: 40, xp: 120),
                .init(id: "spring-days", title: "Walk 1 km on 10 spring days", goal: .activeDays(10), coins: 40, xp: 120),
            ],
            communityGoalKilometres: 12_000, titleID: "bloom-bringer"),
        SeasonalEvent(
            id: "ocean-expedition", name: "Ocean Expedition", tagline: "Together we walk to the sea.",
            start: .init(6, 20), end: .init(7, 18), season: .summer, spriteID: "shell",
            tiers: [
                .init(kilometres: 5, coins: 30, xp: 100, itemIDs: []),
                .init(kilometres: 15, coins: 50, xp: 150, itemIDs: ["pet-sailor-hat"]),
                .init(kilometres: 30, coins: 80, xp: 250, itemIDs: []),
                .init(kilometres: 50, coins: 120, xp: 400, itemIDs: []),
            ],
            quests: [
                .init(id: "ocean-km", title: "Walk 25 km toward the sea", goal: .kilometres(25), coins: 50, xp: 150),
                .init(id: "ocean-days", title: "Walk on 8 summer days", goal: .activeDays(8), coins: 40, xp: 120),
            ],
            communityGoalKilometres: 20_000, titleID: "ocean-voyager"),
        SeasonalEvent(
            id: "starfall-festival", name: "Starfall Festival", tagline: "The sky rains stars for three weeks.",
            start: .init(8, 5), end: .init(8, 25), season: .summer, spriteID: "starfall",
            tiers: [
                .init(kilometres: 5, coins: 30, xp: 100, itemIDs: []),
                .init(kilometres: 12, coins: 50, xp: 150, itemIDs: ["pet-star-cape"]),
                .init(kilometres: 25, coins: 80, xp: 250, itemIDs: []),
                .init(kilometres: 40, coins: 120, xp: 400, itemIDs: []),
            ],
            quests: [
                .init(id: "starfall-nights", title: "Walk on 6 festival days", goal: .activeDays(6), coins: 40, xp: 120),
                .init(id: "starfall-critters", title: "Spot 2 creatures under the stars", goal: .creatures(2), coins: 30, xp: 100),
            ],
            communityGoalKilometres: 8_000, titleID: "star-catcher"),
    ]

    public static func event(withID id: String) -> SeasonalEvent? { all.first { $0.id == id } }

    /// The run of `event` that contains `day`, or the next one after it.
    public static func run(of event: SeasonalEvent, around day: LocalDay) -> EventRun {
        for year in [day.year - 1, day.year, day.year + 1] {
            let start = LocalDay(year: year, month: event.start.month, day: event.start.day)
            let wraps = (event.end.month, event.end.day) < (event.start.month, event.start.day)
            let end = LocalDay(year: wraps ? year + 1 : year, month: event.end.month, day: event.end.day)
            if day <= end { return EventRun(event: event, startDay: start, endDay: end) }
        }
        let start = LocalDay(year: day.year + 1, month: event.start.month, day: event.start.day)
        return EventRun(event: event, startDay: start, endDay: start)
    }

    /// The events running on `day`.
    public static func active(on day: LocalDay) -> [EventRun] {
        all.map { run(of: $0, around: day) }.filter { $0.contains(day) }
    }

    /// The next event to start after `day`.
    public static func next(after day: LocalDay) -> EventRun? {
        all.map { run(of: $0, around: day) }.filter { $0.startDay > day }.min { $0.startDay < $1.startDay }
    }

    /// True while `itemID` can only be earned (its event is running).
    public static func isEventExclusiveNow(_ itemID: String, on day: LocalDay) -> Bool {
        active(on: day).contains { run in run.event.tiers.contains { $0.itemIDs.contains(itemID) } }
    }
}

extension JournalEvents {
    public static func eventTier(_ run: EventRun, tier: Int, on day: LocalDay) -> JournalEntry {
        let last = tier == run.event.tiers.count
        return JournalEntry(id: "event-\(run.id)-tier-\(tier)", kind: .event, day: day,
                            title: last ? "\(run.event.name) complete!" : "\(run.event.name): tier \(tier)",
                            detail: last ? "Every tier of this year's \(run.event.name). See you next year!" : run.event.tagline,
                            iconID: run.event.spriteID)
    }
}
