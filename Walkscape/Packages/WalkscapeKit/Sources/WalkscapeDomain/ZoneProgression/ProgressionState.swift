import Foundation

/// Shown once when the walker reaches new zones. Several boundaries crossed
/// in a single update collapse into one celebration.
public struct ZoneCelebration: Hashable, Sendable {
    /// The furthest zone reached in this update.
    public let zone: Zone
    /// How many boundaries were crossed in this update (>= 1).
    public let boundariesCrossed: Int
    /// Zones reached for the first time ever, with their collectibles.
    public let newDiscoveries: [Collectible]
}

public struct ProgressionEvent: Hashable, Sendable {
    public var celebration: ZoneCelebration?
    public var dayDidReset: Bool
    /// The update was for an earlier day than the current one and only adjusted history.
    public var wasLateUpdate: Bool

    public static let none = ProgressionEvent(celebration: nil, dayDidReset: false, wasLateUpdate: false)
}

/// Persisted progression. Updated only through `apply(_:using:)`, which is
/// idempotent: re-applying the same (or a lower) distance never re-unlocks
/// or re-celebrates anything.
public struct ProgressionState: Codable, Hashable, Sendable {
    /// The local day `todayHighestZoneIndex` / `todayBestMeters` belong to.
    public private(set) var day: LocalDay?
    /// Highest zone index reached today. Monotonic within a day.
    public private(set) var todayHighestZoneIndex: Int
    /// Highest distance seen today. HealthKit totals can be revised down;
    /// unlocks never are.
    public private(set) var todayBestMeters: Int
    /// Zones ever reached (permanent discoveries).
    public private(set) var discoveredZoneIDs: Set<String>
    /// Collectibles ever found.
    public private(set) var collectedItemIDs: Set<String>
    /// Best distance per day, keyed by ISO local date. Lifetime = sum.
    public private(set) var dailyBestMeters: [String: Int]
    /// Best single-day distance ever.
    public private(set) var bestDayMeters: Int

    public init() {
        day = nil
        todayHighestZoneIndex = 0
        todayBestMeters = 0
        discoveredZoneIDs = []
        collectedItemIDs = []
        dailyBestMeters = [:]
        bestDayMeters = 0
    }

    public var lifetimeMeters: Int { dailyBestMeters.values.reduce(0, +) }

    /// Days with at least `minimumMeters` walked.
    public func activeDays(minimumMeters: Int = 1_000) -> Int {
        dailyBestMeters.values.filter { $0 >= minimumMeters }.count
    }

    public mutating func apply(_ progress: DailyProgress, using engine: ZoneProgressionEngine) -> ProgressionEvent {
        let meters = max(0, progress.distanceMeters)
        let key = progress.localDate.isoString

        // A delayed update for an earlier day: record history, nothing else.
        if let day, progress.localDate < day {
            recordHistory(key: key, meters: meters)
            return ProgressionEvent(celebration: nil, dayDidReset: false, wasLateUpdate: true)
        }

        var event = ProgressionEvent.none
        if day != progress.localDate {
            day = progress.localDate
            todayHighestZoneIndex = 0
            todayBestMeters = 0
            event.dayDidReset = true
            discover(engine.catalog.zone(at: 0))
        }

        recordHistory(key: key, meters: meters)
        todayBestMeters = max(todayBestMeters, meters)

        let reachedIndex = engine.catalog.zoneIndex(forMeters: todayBestMeters)
        guard reachedIndex > todayHighestZoneIndex else { return event }

        var newDiscoveries: [Collectible] = []
        for index in (todayHighestZoneIndex + 1)...reachedIndex {
            if let item = discover(engine.catalog.zone(at: index)) { newDiscoveries.append(item) }
        }
        let crossed = reachedIndex - todayHighestZoneIndex
        todayHighestZoneIndex = reachedIndex
        event.celebration = ZoneCelebration(zone: engine.catalog.zone(at: reachedIndex),
                                            boundariesCrossed: crossed,
                                            newDiscoveries: newDiscoveries)
        return event
    }

    /// Combines two devices' progression (a cloud save). Everything here only
    /// ever grows, so the merge takes the union of discoveries and the best
    /// distance per day; today's counters come from the later day.
    public func merged(with other: ProgressionState) -> ProgressionState {
        var result = self
        result.discoveredZoneIDs.formUnion(other.discoveredZoneIDs)
        result.collectedItemIDs.formUnion(other.collectedItemIDs)
        result.dailyBestMeters.merge(other.dailyBestMeters) { max($0, $1) }
        result.bestDayMeters = max(bestDayMeters, other.bestDayMeters)
        let otherIsLater = other.day.map { theirs in day.map { theirs > $0 } ?? true } ?? false
        switch (day, other.day) {
        case _ where otherIsLater:
            result.day = other.day
            result.todayHighestZoneIndex = other.todayHighestZoneIndex
            result.todayBestMeters = other.todayBestMeters
        case let (mine?, theirs?) where theirs == mine:
            result.todayHighestZoneIndex = max(todayHighestZoneIndex, other.todayHighestZoneIndex)
            result.todayBestMeters = max(todayBestMeters, other.todayBestMeters)
        default:
            break
        }
        return result
    }

    private mutating func recordHistory(key: String, meters: Int) {
        let best = max(dailyBestMeters[key] ?? 0, meters)
        dailyBestMeters[key] = best
        bestDayMeters = max(bestDayMeters, best)
    }

    /// Marks a zone discovered. Returns its collectible if this is the first time.
    @discardableResult
    private mutating func discover(_ zone: Zone) -> Collectible? {
        guard discoveredZoneIDs.insert(zone.id).inserted else { return nil }
        guard let item = zone.discovery, collectedItemIDs.insert(item.id).inserted else { return nil }
        return item
    }
}
