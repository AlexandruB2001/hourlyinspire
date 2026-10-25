import Foundation

/// A calendar day in a specific time zone ("2026-10-25").
///
/// Daily progress resets at local midnight, so every daily total is keyed by
/// a `LocalDay` rather than a `Date`.
public struct LocalDay: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local day that contains `date` in `timeZone`.
    public init(date: Date, timeZone: TimeZone) {
        let components = LocalDay.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    /// Local midnight to the next local midnight. Uses the calendar rather than
    /// adding 24 hours, so 23- and 25-hour DST days are handled correctly.
    public func interval(in timeZone: TimeZone) -> DateInterval {
        let calendar = LocalDay.calendar(timeZone)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    public func adding(days: Int) -> LocalDay {
        let utc = TimeZone(identifier: "UTC")!
        let calendar = LocalDay.calendar(utc)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return LocalDay(date: calendar.date(byAdding: .day, value: days, to: start)!, timeZone: utc)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let day = LocalDay(isoString: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid local day \(string)"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
