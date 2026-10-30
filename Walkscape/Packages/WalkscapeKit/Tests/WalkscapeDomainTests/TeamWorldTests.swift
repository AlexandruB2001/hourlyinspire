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

    func testEveryWorldHasWildlifeATreasureAndATitle() {
        let creatureIDs = TeamWorldContent.allCreatures.map(\.id)
        XCTAssertEqual(Set(creatureIDs).count, creatureIDs.count)
        XCTAssertTrue(Set(creatureIDs).isDisjoint(with: WildlifeCatalog.all.map(\.id)), "world wildlife stays out of the trail book")
        for world in worlds {
            XCTAssertEqual(world.creatures.count, 3, world.id)
            let zoneIDs = Set(world.zones.map(\.id))
            for creature in world.creatures {
                XCTAssertTrue(Set(creature.zoneIDs).isSubset(of: zoneIDs), creature.id)
            }
            let treasure = try! XCTUnwrap(world.treasure)
            XCTAssertNil(TreasureCatalog.treasure(withID: treasure.id), "world treasures stay out of the trail book")
            XCTAssertNotNil(TitleCatalog.title(withID: "world-\(world.id)"), world.id)
        }
    }

    func testSightingsNeedAReachedZoneAndAreTheSameForTheWholeTeam() {
        let world = worlds[0]
        let start = TeamWorldCatalog.startMeters(of: world)
        let atGate = TeamWorldProgress(teamMeters: start)
        let days = (1...28).map { LocalDay(year: 2027, month: 2, day: $0) }
        let seen = Set(days.flatMap { TeamWorldContent.sightings(on: $0, progress: atGate).map(\.id) })
        XCTAssertTrue(seen.isSubset(of: ["glow-moth"]), "only creatures living at the Moonlit Gate")
        XCTAssertTrue(seen.contains("glow-moth"), "a common creature turns up within a month")
        XCTAssertTrue(TeamWorldContent.sightings(on: days[0], progress: TeamWorldProgress(teamMeters: start - 1)).isEmpty)
        XCTAssertEqual(TeamWorldContent.sightings(on: days[3], progress: atGate),
                       TeamWorldContent.sightings(on: days[3], progress: atGate))
    }

    func testWorldQuests() {
        let world = worlds[0]
        let start = TeamWorldCatalog.startMeters(of: world)
        let fresh = world.quests(progress: TeamWorldProgress(teamMeters: start), seenCreatures: [], challengeDone: false)
        XCTAssertEqual(fresh.map(\.kind), [.pathfinder, .naturalist, .together])
        XCTAssertFalse(fresh.contains(where: \.isComplete))
        XCTAssertEqual(fresh[0].done, 1)
        XCTAssertEqual(fresh[1].treasure?.id, "moonlit-harp")
        XCTAssertEqual(fresh[2].reward.id, world.challengeReward.id)
        let done = world.quests(progress: TeamWorldProgress(teamMeters: start + world.lengthMeters),
                                seenCreatures: Set(world.creatures.map(\.id)), challengeDone: true)
        XCTAssertTrue(done.allSatisfy(\.isComplete))
        let ids = worlds.flatMap { $0.quests(progress: TeamWorldProgress(teamMeters: 0), seenCreatures: [], challengeDone: false) }
            .map(\.reward.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testWorldTitleNeedsTheLastZone() {
        let world = worlds[0]
        var ledger = RewardLedger()
        var wallet = WalletState()
        let facts = { ProfileFacts(progression: ProgressionState(), explorerLevel: 1, ledger: ledger, journal: JourneyJournal(),
                                   companionStage: nil) }
        let title = TitleCatalog.title(withID: "world-enchanted-forest")!
        XCTAssertFalse(title.requirement.isMet(by: facts()))
        _ = ledger.claim(world.zones[0].reward, into: &wallet)
        XCTAssertFalse(title.requirement.isMet(by: facts()))
        _ = ledger.claim(world.zones.last!.reward, into: &wallet)
        XCTAssertTrue(title.requirement.isMet(by: facts()))
    }

    func testWorldFindsDoNotCountInTheTrailBooks() {
        var collections = CollectionState()
        let day = LocalDay(year: 2027, month: 2, day: 1)
        collections.recordSightings(worlds[0].creatures, on: day)
        collections.recordTreasure(worlds[0].treasure!, on: day)
        XCTAssertEqual(collections.trailWildlifeCount, 0)
        XCTAssertEqual(collections.trailTreasureCount, 0)
        collections.recordSightings([WildlifeCatalog.all[0]], on: day)
        XCTAssertEqual(collections.trailWildlifeCount, 1)
    }

    func testServerZoneDistancesMatchTheApp() throws {
        let migration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // WalkscapeDomainTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // WalkscapeKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // Walkscape
            .appendingPathComponent("Walkscape/supabase/migrations/20261106000001_team_worlds.sql")
        let sql = try String(contentsOf: migration, encoding: .utf8)
        var rows = 0
        for world in worlds {
            for zone in world.zones {
                let meters = TeamWorldCatalog.startMeters(of: world) + zone.metersFromWorldStart
                XCTAssertTrue(sql.contains("('\(zone.id)', '\(world.id)', \(meters))"), "\(zone.id) should be at \(meters) m")
                rows += 1
            }
        }
        XCTAssertEqual(sql.components(separatedBy: "', '").count - 1, rows, "no extra zones on the server")
    }

    func testEverythingAfterTheLastWorldStaysInIt() {
        let huge = TeamWorldProgress(teamMeters: 100_000_000)
        XCTAssertEqual(huge.currentWorld?.id, worlds.last?.id)
        XCTAssertNil(huge.nextZone(in: worlds.last!))
    }
}
