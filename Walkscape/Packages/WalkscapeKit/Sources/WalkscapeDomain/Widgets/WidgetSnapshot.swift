import Foundation

/// What the home-screen widgets show. The app writes it to the shared app
/// group after each refresh; the widget only reads it (widgets can't read
/// Apple Health while the phone is locked).
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let appGroup = "group.com.alexandrub.walkscape"
    public static let storageKey = "walkscape.widget.v1"

    public var avatarID: String
    public var outfit: [String]
    public var companionSpeciesID: String?
    public var companionKilometres: Int
    public var companionAccessories: [String]
    public var companionSkinID: String?
    public var day: LocalDay
    public var todayMeters: Int
    public var todaySteps: Int?
    public var totalMeters: Int
    /// Monday to today. Nil in snapshots saved by older builds.
    public var weekMeters: Int?
    public var zoneName: String
    public var biome: Biome
    public var nextZoneName: String
    public var metersToNextZone: Int
    public var updatedAt: Date

    public init(avatarID: String, outfit: [String], companionSpeciesID: String?, companionKilometres: Int,
                companionAccessories: [String], companionSkinID: String?, day: LocalDay, todayMeters: Int,
                todaySteps: Int?, totalMeters: Int, zoneName: String, biome: Biome, nextZoneName: String,
                metersToNextZone: Int, updatedAt: Date, weekMeters: Int? = nil) {
        self.avatarID = avatarID
        self.outfit = outfit
        self.companionSpeciesID = companionSpeciesID
        self.companionKilometres = companionKilometres
        self.companionAccessories = companionAccessories
        self.companionSkinID = companionSkinID
        self.day = day
        self.todayMeters = todayMeters
        self.todaySteps = todaySteps
        self.totalMeters = totalMeters
        self.weekMeters = weekMeters
        self.zoneName = zoneName
        self.biome = biome
        self.nextZoneName = nextZoneName
        self.metersToNextZone = metersToNextZone
        self.updatedAt = updatedAt
    }

    /// Today's numbers belong to the day they were recorded: after midnight
    /// the widget shows a fresh start at the Meadow until the app updates it.
    public func showing(on today: LocalDay) -> WidgetSnapshot {
        guard today > day else { return self }
        let start = ZoneCatalog.standard
        var fresh = self
        fresh.day = today
        fresh.todayMeters = 0
        fresh.todaySteps = nil
        if TeamWeek.start(of: today) != TeamWeek.start(of: day), weekMeters != nil { fresh.weekMeters = 0 }
        fresh.zoneName = start.zones[0].name
        fresh.biome = start.zones[0].biome
        fresh.nextZoneName = start.zones[1].name
        fresh.metersToNextZone = start.zones[0].lengthMeters
        return fresh
    }

    /// Metres walked this week (Monday to `today`), counting today's live number
    /// even when the saved best for today hasn't caught up yet.
    public static func weekTotal(dailyBestMeters: [String: Int], today: LocalDay, todayMeters: Int) -> Int {
        let week = TeamWeek.start(of: today)
        var total = 0
        var day = week
        while day < today {
            total += dailyBestMeters[day.isoString] ?? 0
            day = day.adding(days: 1)
        }
        return total + max(todayMeters, dailyBestMeters[today.isoString] ?? 0)
    }

    /// Shown in the widget gallery and before the app has written anything.
    public static let preview = WidgetSnapshot(
        avatarID: "fern", outfit: ["straw-hat"], companionSpeciesID: "mossling", companionKilometres: 24,
        companionAccessories: [], companionSkinID: nil, day: LocalDay(year: 2026, month: 10, day: 30),
        todayMeters: 4_250, todaySteps: 5_830, totalMeters: 128_400, zoneName: "Rolling Hills", biome: .rollingHills,
        nextZoneName: "Lakeside", metersToNextZone: 750, updatedAt: Date(timeIntervalSince1970: 1_793_000_000), weekMeters: 23_600)
}
