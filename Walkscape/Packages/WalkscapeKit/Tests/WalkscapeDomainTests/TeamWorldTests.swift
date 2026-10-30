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

    func testEachWorldHasItsOwnScenery() {
        let own: [String: Biome] = ["enchanted-forest": .enchantedForest, "crystal-kingdom": .crystalPalace,
                                    "forgotten-desert": .desertRuins, "floating-isles": .skyIslands,
                                    "ancient-kingdom": .ancientCity]
        for world in worlds {
            XCTAssertEqual(world.zones.first?.biome, own[world.id], "the world map shows its own art")
            XCTAssertTrue(world.zones.allSatisfy { !$0.biome.isTeamWorld || $0.biome == own[world.id] }, world.id)
        }
    }

    func testTheSoloTrailNeverShowsTeamWorldScenery() {
        let trail = ZoneCatalog.standard
        XCTAssertFalse(trail.zones.contains { $0.biome.isTeamWorld })
        XCTAssertFalse((0..<60).map { trail.zone(at: trail.zones.count + $0).biome }.contains { $0.isTeamWorld })
        XCTAssertEqual(Biome.trailBiomes.count, 20)
    }

    func testEverythingAfterTheLastWorldStaysInIt() {
        let huge = TeamWorldProgress(teamMeters: 100_000_000)
        XCTAssertEqual(huge.currentWorld?.id, worlds.last?.id)
        XCTAssertNil(huge.nextZone(in: worlds.last!))
    }
}
