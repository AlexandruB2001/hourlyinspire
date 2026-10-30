import XCTest
@testable import WalkscapeDomain

final class WorldEventTests: XCTestCase {
    let start = LocalDay(year: 2026, month: 11, day: 1)
    let allZones = Set(ZoneCatalog.standard.zones.map(\.id))

    func testSeasonsFollowTheCalendarAndFlipSouth() {
        XCTAssertEqual(Season.of(LocalDay(year: 2026, month: 1, day: 10)), .winter)
        XCTAssertEqual(Season.of(LocalDay(year: 2026, month: 4, day: 10)), .spring)
        XCTAssertEqual(Season.of(LocalDay(year: 2026, month: 7, day: 10)), .summer)
        XCTAssertEqual(Season.of(LocalDay(year: 2026, month: 10, day: 10)), .autumn)
        XCTAssertEqual(Season.of(LocalDay(year: 2026, month: 12, day: 1)), .winter)
        XCTAssertEqual(Season.of(LocalDay(year: 2026, month: 1, day: 10), southernHemisphere: true), .summer)
        XCTAssertEqual(Season.of(LocalDay(year: 2026, month: 7, day: 10), southernHemisphere: true), .winter)
        XCTAssertTrue(Season.isSouthernHemisphere(TimeZone(identifier: "Australia/Sydney")!))
        XCTAssertFalse(Season.isSouthernHemisphere(TimeZone(identifier: "Europe/London")!))
    }

    func testCatalogPointsAtRealZonesCreaturesAndSprites() {
        XCTAssertEqual(Set(WorldEventCatalog.all.map(\.id)).count, WorldEventCatalog.all.count)
        for event in WorldEventCatalog.all {
            XCTAssertTrue(Set(event.zoneIDs).isSubset(of: allZones), event.id)
            if case .creature(let id) = event.bonus { XCTAssertNotNil(WildlifeCatalog.creature(withID: id), event.id) }
        }
    }

    func testTheScheduleIsFixedPerDayAndCapped() {
        var seen = Set<String>()
        for offset in 0..<365 {
            let day = start.adding(days: offset)
            let season = Season.of(day)
            let a = WorldEventCatalog.schedule(for: day, season: season, exploredZoneIDs: allZones)
            XCTAssertEqual(a, WorldEventCatalog.schedule(for: day, season: season, exploredZoneIDs: allZones))
            XCTAssertLessThanOrEqual(a.count, WorldEventCatalog.maxPerDay)
            for scheduled in a {
                if case .season(let s) = scheduled.event.window { XCTAssertEqual(s, season) }
                if case .eveningIn(let s) = scheduled.event.window { XCTAssertEqual(s, season) }
                XCTAssertTrue(allZones.contains(scheduled.zoneID))
                XCTAssertTrue(scheduled.id.hasSuffix(day.isoString), "rewards are per event per day")
            }
            seen.formUnion(a.map(\.event.id))
        }
        XCTAssertGreaterThanOrEqual(seen.count, WorldEventCatalog.all.count - 2, "over a year most events turn up")
    }

    func testLostChestsOnlyAppearInExploredZones() {
        for offset in 0..<400 {
            let day = start.adding(days: offset)
            let scheduled = WorldEventCatalog.schedule(for: day, season: Season.of(day), exploredZoneIDs: ["meadow", "riverside", "lakeside"])
            for event in scheduled where event.event.id == "lost-chest" {
                XCTAssertTrue(["riverside", "lakeside"].contains(event.zoneID))
            }
            let fresh = WorldEventCatalog.schedule(for: day, season: Season.of(day), exploredZoneIDs: ["meadow"])
            XCTAssertFalse(fresh.contains { $0.event.id == "lost-chest" }, "nothing explored beyond the start")
        }
    }

    func testEveningEventsWaitForTheEvening() {
        let star = WorldEventCatalog.event(withID: "shooting-star")!
        XCTAssertFalse(star.isOpen(season: .autumn, hour: 12))
        XCTAssertTrue(star.isOpen(season: .autumn, hour: 19))
        let fireflies = WorldEventCatalog.event(withID: "fireflies")!
        XCTAssertFalse(fireflies.isOpen(season: .winter, hour: 21))
        XCTAssertTrue(fireflies.isOpen(season: .summer, hour: 21))
    }
}
