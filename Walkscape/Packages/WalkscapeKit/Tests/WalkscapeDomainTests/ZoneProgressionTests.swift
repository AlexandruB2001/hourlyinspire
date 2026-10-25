import XCTest
@testable import WalkscapeDomain

final class ZoneProgressionTests: XCTestCase {
    let engine = ZoneProgressionEngine()
    let today = LocalDay(year: 2026, month: 10, day: 25)

    func progress(_ meters: Int, day: LocalDay? = nil) -> DailyProgress {
        DailyProgress(userID: "me", localDate: day ?? today, timeZoneIdentifier: "Europe/London",
                      steps: meters, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date())
    }

    // MARK: Boundaries

    func testZeroMetersIsMeadow() {
        let p = engine.progress(forMeters: 0)
        XCTAssertEqual(p.currentZone.id, "meadow")
        XCTAssertEqual(p.nextZone.id, "riverside")
        XCTAssertEqual(p.metersToNextZone, 1_000)
        XCTAssertEqual(p.fractionThroughZone, 0)
    }

    func test999MetersIsStillMeadow() {
        let p = engine.progress(forMeters: 999)
        XCTAssertEqual(p.currentZone.id, "meadow")
        XCTAssertEqual(p.metersToNextZone, 1)
    }

    func test1000MetersIsRiverside() {
        let p = engine.progress(forMeters: 1_000)
        XCTAssertEqual(p.currentZone.id, "riverside")
        XCTAssertEqual(p.metersIntoZone, 0)
        XCTAssertEqual(p.metersToNextZone, 1_000)
    }

    func test1999And2000Meters() {
        XCTAssertEqual(engine.progress(forMeters: 1_999).currentZone.id, "riverside")
        XCTAssertEqual(engine.progress(forMeters: 2_000).currentZone.id, "pine-forest")
    }

    func testBriefExample() {
        let p = engine.progress(forMeters: 2_400)
        XCTAssertEqual(p.currentZone.name, "Pine Forest")
        XCTAssertEqual(p.nextZone.name, "Rolling Hills")
        XCTAssertEqual(p.metersToNextZone, 600)
        XCTAssertEqual(DistanceFormatting.remaining(p.metersToNextZone), "600 m")
    }

    func testLargeDistancesContinueBeyondCatalog() {
        let summit = engine.progress(forMeters: 9_500)
        XCTAssertEqual(summit.currentZone.id, "summit")
        XCTAssertEqual(summit.nextZone.id, "beyond-1")

        let beyond = engine.progress(forMeters: 10_000)
        XCTAssertEqual(beyond.currentZone.id, "beyond-1")
        XCTAssertEqual(beyond.zoneIndex, 10)

        let huge = engine.progress(forMeters: 1_000_000_000)
        XCTAssertEqual(huge.zoneIndex, 1_000_000)
        XCTAssertEqual(huge.metersToNextZone, 1_000)
        XCTAssertEqual(engine.catalog.zone(withID: huge.currentZone.id), huge.currentZone)
    }

    func testNegativeDistanceClamps() {
        XCTAssertEqual(engine.progress(forMeters: -50).currentZone.id, "meadow")
    }

    func testCatalogValidation() {
        let a = Zone(id: "a", name: "A", tagline: "", detail: "", biome: .meadow, startMeters: 0, endMeters: 500)
        let b = Zone(id: "b", name: "B", tagline: "", detail: "", biome: .meadow, startMeters: 600, endMeters: 900)
        XCTAssertThrowsError(try ZoneCatalog(zones: [])) { XCTAssertEqual($0 as? ZoneCatalog.ValidationError, .empty) }
        XCTAssertThrowsError(try ZoneCatalog(zones: [a, b])) {
            XCTAssertEqual($0 as? ZoneCatalog.ValidationError, .gap(afterZoneID: "a"))
        }
        XCTAssertThrowsError(try ZoneCatalog(zones: [b])) {
            XCTAssertEqual($0 as? ZoneCatalog.ValidationError, .doesNotStartAtZero)
        }
    }

    func testVariableLengthZonesFromJSON() throws {
        let json = """
        {"zones":[
          {"id":"a","name":"A","tagline":"","detail":"","biome":"meadow","startMeters":0,"endMeters":500},
          {"id":"b","name":"B","tagline":"","detail":"","biome":"village","startMeters":500,"endMeters":2000}
        ],"beyondLengthMeters":250}
        """
        let catalog = try JSONDecoder().decode(ZoneCatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.zone(forMeters: 499).id, "a")
        XCTAssertEqual(catalog.zone(forMeters: 500).id, "b")
        XCTAssertEqual(catalog.zone(forMeters: 1_999).id, "b")
        XCTAssertEqual(catalog.zone(forMeters: 2_000).id, "beyond-1")
        XCTAssertEqual(catalog.zone(forMeters: 2_250).id, "beyond-2")
    }

    // MARK: Unlocking

    func testFirstUpdateResetsDayAndDiscoversMeadow() {
        var state = ProgressionState()
        let event = state.apply(progress(300), using: engine)
        XCTAssertTrue(event.dayDidReset)
        XCTAssertNil(event.celebration)
        XCTAssertEqual(state.discoveredZoneIDs, ["meadow"])
        XCTAssertEqual(state.collectedItemIDs, ["clover"])
    }

    func testCrossingBoundaryCelebratesOnce() {
        var state = ProgressionState()
        _ = state.apply(progress(950), using: engine)
        let event = state.apply(progress(1_010), using: engine)
        XCTAssertEqual(event.celebration?.zone.id, "riverside")
        XCTAssertEqual(event.celebration?.boundariesCrossed, 1)
        XCTAssertEqual(event.celebration?.newDiscoveries.map(\.id), ["river-stone"])

        // Same update again, or a slightly lower revised total: nothing new.
        XCTAssertNil(state.apply(progress(1_010), using: engine).celebration)
        XCTAssertNil(state.apply(progress(990), using: engine).celebration)
        XCTAssertNil(state.apply(progress(1_200), using: engine).celebration)
        XCTAssertEqual(state.todayHighestZoneIndex, 1)
        XCTAssertEqual(state.todayBestMeters, 1_200)
    }

    func testDelayedUpdateCollapsesMultipleCrossings() {
        var state = ProgressionState()
        _ = state.apply(progress(200), using: engine)
        let event = state.apply(progress(4_300), using: engine)
        XCTAssertEqual(event.celebration?.zone.id, "lakeside")
        XCTAssertEqual(event.celebration?.boundariesCrossed, 4)
        XCTAssertEqual(event.celebration?.newDiscoveries.count, 4)
        XCTAssertEqual(state.discoveredZoneIDs.count, 5)
    }

    func testDiscoveriesArePermanentAcrossDays() {
        var state = ProgressionState()
        _ = state.apply(progress(2_500), using: engine)
        let tomorrow = today.adding(days: 1)
        let reset = state.apply(progress(100, day: tomorrow), using: engine)
        XCTAssertTrue(reset.dayDidReset)
        XCTAssertEqual(state.todayHighestZoneIndex, 0)
        XCTAssertEqual(state.todayBestMeters, 100)

        // Zones are celebrated again each day, but are not new discoveries.
        let event = state.apply(progress(1_100, day: tomorrow), using: engine)
        XCTAssertEqual(event.celebration?.zone.id, "riverside")
        XCTAssertEqual(event.celebration?.newDiscoveries, [])
        XCTAssertEqual(state.lifetimeMeters, 2_500 + 1_100)
    }

    func testLateUpdateForPreviousDayOnlyAdjustsHistory() {
        var state = ProgressionState()
        let yesterday = today.adding(days: -1)
        _ = state.apply(progress(500), using: engine)
        let event = state.apply(progress(6_000, day: yesterday), using: engine)
        XCTAssertTrue(event.wasLateUpdate)
        XCTAssertNil(event.celebration)
        XCTAssertEqual(state.day, today)
        XCTAssertEqual(state.todayBestMeters, 500)
        XCTAssertEqual(state.dailyBestMeters[yesterday.isoString], 6_000)
        XCTAssertEqual(state.bestDayMeters, 6_000)
    }

    func testBeyondCatalogUnlocksDoNotCrash() {
        var state = ProgressionState()
        let event = state.apply(progress(25_000), using: engine)
        XCTAssertEqual(event.celebration?.zone.id, "beyond-16")
        XCTAssertEqual(event.celebration?.boundariesCrossed, 25)
        XCTAssertEqual(state.collectedItemIDs.count, 10)
    }

    func testStateRoundTripsThroughJSON() throws {
        var state = ProgressionState()
        _ = state.apply(progress(3_100), using: engine)
        let decoded = try JSONDecoder().decode(ProgressionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }

    // MARK: Achievements

    func testAchievements() {
        var state = ProgressionState()
        let first = AchievementCatalog.standard.first { $0.id == "first-steps" }!
        let regular = AchievementCatalog.standard.first { $0.id == "regular" }!
        _ = state.apply(progress(800), using: engine)
        XCTAssertFalse(first.isUnlocked(by: state))
        XCTAssertEqual(first.progress(for: state), 0.8, accuracy: 0.0001)
        _ = state.apply(progress(1_000), using: engine)
        XCTAssertTrue(first.isUnlocked(by: state))
        XCTAssertFalse(regular.isUnlocked(by: state))
        _ = state.apply(progress(1_500, day: today.adding(days: 1)), using: engine)
        _ = state.apply(progress(2_000, day: today.adding(days: 2)), using: engine)
        XCTAssertTrue(regular.isUnlocked(by: state))
    }
}
