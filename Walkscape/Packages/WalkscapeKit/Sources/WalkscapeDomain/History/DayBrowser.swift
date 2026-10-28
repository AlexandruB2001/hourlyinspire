import Foundation

/// Which past day the World screen is showing. Never goes past today.
public struct DayBrowser: Hashable, Sendable {
    public let today: LocalDay
    public let earliest: LocalDay
    public private(set) var selected: LocalDay

    /// `earliest` is clamped to `today`; how far back is the caller's choice.
    public init(today: LocalDay, earliest: LocalDay, selected: LocalDay? = nil) {
        self.today = today
        self.earliest = min(earliest, today)
        self.selected = min(max(selected ?? today, self.earliest), today)
    }

    /// Earliest day worth browsing: the first recorded day, or `lookback`
    /// days ago if Health may hold older data than the app has seen.
    public static func earliestDay(today: LocalDay, recordedDays: some Sequence<String>, lookback: Int) -> LocalDay {
        let recorded = recordedDays.compactMap(LocalDay.init(isoString:)).min() ?? today
        return min(recorded, today.adding(days: -max(0, lookback)))
    }

    public var isToday: Bool { selected == today }
    public var canGoBack: Bool { selected > earliest }
    public var canGoForward: Bool { selected < today }

    public mutating func goBack() { if canGoBack { selected = selected.adding(days: -1) } }
    public mutating func goForward() { if canGoForward { selected = selected.adding(days: 1) } }
    public mutating func jumpToToday() { selected = today }
}
