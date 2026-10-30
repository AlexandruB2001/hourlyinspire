import XCTest
@testable import WalkscapeDomain

final class TeamWorldTests: XCTestCase {
    let worlds = TeamWorldCatalog.worlds

    func testFiveWorldsWithGrowingZonesAndUniqueIDs() {
        XCTAssertEqual(worlds.count, 5)
        let zoneIDs = worlds.flatMap { $0.zones.map(\.id) }
        XCTAssertEqual(Set(zoneIDs).count, zoneIDs.count)
        XCTAssertEqual(Set(worlds.flatMap { $0.zones.map(\.relic.id) }).count, zoneIDs.count)
        for world in worlds {
            XCTAssertGreaterThanOrEqual(world.zones.count, 4, world.id)
            XCTAssertEqual(world.zones.first?.metersFromWorldStart, 0, world.id)
            let marks = world.zones.map(\.metersFromWorldStart)
            XCTAssertEqual(marks, marks.sorted(), world.id)
            XCTAssertEqual(Set(marks).count, marks.count, world.id)
            // Far beyond one walker: every world needs hundreds of team kilometres.
            XCTAssertGreaterThanOrEqual(world.lengthMeters, 500_000, world.id)
        }
    }

    func testTheFirstWorldOpensAfterTheSummitRelay() {
        let start = TeamWorldCatalog.startMeters(of: worlds[0])
        XCTAssertEqual(start, 100_000, "Meadow Ramble 25 km + Summit Relay 75 km")
        XCTAssertFalse(TeamWorldProgress(teamMeters: start - 1).isUnlocked)
        XCTAssertEqual(TeamWorldProgress(teamMeters: 40_000).metersToUnlock, 60_000)
        let open = TeamWorldProgress(teamMeters: start)
        XCTAssertTrue(open.isUnlocked)
        XCTAssertEqual(open.currentWorld?.id, "enchanted-forest")
        XCTAssertEqual(open.reachedZones.map(\.id), ["ef-gate"])
    }

    func testWorldsFollowEachOther() {
        let second = TeamWorldCatalog.startMeters(of: worlds[1])
        XCTAssertEqual(second, TeamWorldCatalog.startMeters(of: worlds[0]) + worlds[0].lengthMeters)
        let progress = TeamWorldProgress(teamMeters: second + 160_000)
        XCTAssertEqual(progress.currentWorld?.id, "crystal-kingdom")
        XCTAssertEqual(progress.reachedZones(in: worlds[0]).count, worlds[0].zones.count, "the first world is fully explored")
        XCTAssertEqual(progress.reachedZones(in: worlds[1]).map(\.id), ["ck-steps", "ck-caverns"])
        XCTAssertEqual(progress.nextZone(in: worlds[1])?.id, "ck-lake")
        XCTAssertTrue(progress.challengeOpen(in: worlds[0]))
        XCTAssertFalse(progress.challengeOpen(in: worlds[1]))
        XCTAssertEqual(progress.meters(in: worlds[1]), 160_000)
    }

    func testRewardsArePerPlayerIDs() {
        let ids = worlds.flatMap { $0.zones.map(\.reward.id) } + worlds.map(\.challengeReward.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.contains { $0.contains("team-") }, "ids don't include the team, so switching teams can't repeat them")
    }

    func testEverythingAfterTheLastWorldStaysInIt() {
        let huge = TeamWorldProgress(teamMeters: 100_000_000)
        XCTAssertEqual(huge.currentWorld?.id, worlds.last?.id)
        XCTAssertNil(huge.nextZone(in: worlds.last!))
    }
}
