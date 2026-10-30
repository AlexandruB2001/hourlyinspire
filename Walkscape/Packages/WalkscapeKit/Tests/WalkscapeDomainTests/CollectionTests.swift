import XCTest
@testable import WalkscapeDomain

final class CollectionTests: XCTestCase {
    let engine = ZoneProgressionEngine()
    let start = LocalDay(year: 2026, month: 11, day: 1)

    func walked(_ days: [Int]) -> ProgressionState {
        var state = ProgressionState()
        for (offset, meters) in days.enumerated() {
            _ = state.apply(DailyProgress(userID: "me", localDate: start.adding(days: offset), timeZoneIdentifier: "UTC",
                                          steps: meters, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date()),
                            using: engine)
        }
        return state
    }

    // MARK: Catalogs

    func testEveryCreatureLivesInARealZoneAndHasArt() {
        let zoneIDs = Set(ZoneCatalog.standard.zones.map(\.id))
        XCTAssertEqual(Set(WildlifeCatalog.all.map(\.id)).count, WildlifeCatalog.all.count)
        XCTAssertGreaterThanOrEqual(WildlifeCatalog.all.count, 24)
        for creature in WildlifeCatalog.all {
            XCTAssertFalse(creature.zoneIDs.isEmpty, creature.id)
            XCTAssertTrue(Set(creature.zoneIDs).isSubset(of: zoneIDs), creature.id)
        }
        for postcard in PostcardCatalog.all { XCTAssertTrue(zoneIDs.contains(postcard.zoneID), postcard.id) }
        XCTAssertEqual(Set(Rarity.allCases), Set(WildlifeCatalog.all.map(\.rarity)), "every rarity appears")
        // Every zone has something to spot.
        for zone in ZoneCatalog.standard.zones {
            XCTAssertTrue(WildlifeCatalog.all.contains { $0.zoneIDs.contains(zone.id) }, zone.id)
        }
    }

    // MARK: Sightings

    func testSightingsAreDeterministicAndNeedTheZone() {
        let day = start
        XCTAssertEqual(WildlifeCatalog.sightings(on: day, zonesReached: ["meadow"]),
                       WildlifeCatalog.sightings(on: day, zonesReached: ["meadow"]))
        for creature in WildlifeCatalog.sightings(on: day, zonesReached: ["meadow"]) {
            XCTAssertTrue(creature.zoneIDs.contains("meadow"))
        }
        XCTAssertTrue(WildlifeCatalog.sightings(on: day, zonesReached: []).isEmpty)
    }

    func testCommonCreaturesAppearRegularlyAndLegendariesRarely() {
        let everywhere = ZoneCatalog.standard.zones.map(\.id)
        var counts: [Rarity: Int] = [:]
        var perRarity: [Rarity: Int] = [:]
        for creature in WildlifeCatalog.all { perRarity[creature.rarity, default: 0] += 1 }
        for offset in 0..<1_000 {
            for creature in WildlifeCatalog.sightings(on: start.adding(days: offset), zonesReached: everywhere) {
                counts[creature.rarity, default: 0] += 1
            }
        }
        let commonRate = Double(counts[.common] ?? 0) / Double(1_000 * perRarity[.common]!)
        let legendaryRate = Double(counts[.legendary] ?? 0) / Double(1_000 * perRarity[.legendary]!)
        XCTAssertEqual(commonRate, 0.30, accuracy: 0.05)
        XCTAssertEqual(legendaryRate, 0.015, accuracy: 0.012)
        XCTAssertGreaterThan(legendaryRate, 0, "legendaries do turn up eventually")
    }

    func testEachCreatureIsRecordedOnceWithItsFirstDate() {
        var state = CollectionState()
        let rabbit = WildlifeCatalog.creature(withID: "rabbit")!
        XCTAssertEqual(state.recordSightings([rabbit], on: start), [rabbit])
        XCTAssertEqual(state.recordSightings([rabbit], on: start.adding(days: 3)), [])
        XCTAssertEqual(state.wildlife["rabbit"], start)

        var other = CollectionState()
        other.recordSightings([rabbit], on: start.adding(days: -2))
        other.recordTreasure(TreasureCatalog.all[0], on: start)
        let merged = state.merged(with: other)
        XCTAssertEqual(merged.wildlife["rabbit"], start.adding(days: -2), "the earliest sighting is kept")
        XCTAssertEqual(merged.treasures.count, 1)
    }

    func testTreasuresNeverRepeat() {
        var owned = Set<String>()
        for i in 0..<TreasureCatalog.all.count {
            let treasure = TreasureCatalog.pick(seed: "seed-\(i)", excluding: owned)!
            XCTAssertFalse(owned.contains(treasure.id))
            owned.insert(treasure.id)
        }
        XCTAssertNil(TreasureCatalog.pick(seed: "more", excluding: owned))
        XCTAssertEqual(TreasureCatalog.pick(seed: "x", excluding: []), TreasureCatalog.pick(seed: "x", excluding: []))
    }

    // MARK: Postcards and memories

    func testPostcardsRewardReturnVisits() {
        let state = walked([1_200, 1_500, 800, 2_000, 1_100])
        let earned = Postcards.earned(in: state)
        // Five days at the Meadow is not yet seven; Riverside (1 km) was reached on 4 days.
        XCTAssertNil(earned["meadow-morning"])
        XCTAssertNil(earned["river-bridge"])
        let more = walked([1_200, 1_500, 800, 2_000, 1_100, 1_000, 300])
        XCTAssertEqual(more.dailyBestMeters.count, 7)
        XCTAssertEqual(Postcards.earned(in: more)["meadow-morning"], start.adding(days: 6))
        XCTAssertEqual(Postcards.earned(in: more)["river-bridge"], start.adding(days: 5))
    }

    func testMemoriesHaveTheDayTheyHappened() {
        let state = walked([600, 1_200, 5_400, 3_000])
        let memories = MemoryCatalog.reached(in: state)
        XCTAssertEqual(memories["first-km"], start.adding(days: 1))
        XCTAssertEqual(memories["first-5k"], start.adding(days: 2))
        XCTAssertEqual(memories["total-10k"], start.adding(days: 3))
        XCTAssertNil(memories["first-10k"])
    }

    func testMilestoneRewardsHaveStableIDs() {
        let half = CollectionProgress(category: .wildlife, found: 14, total: 27)
        XCTAssertEqual(half.percent, 51)
        XCTAssertEqual(half.milestoneRewards.map(\.id), ["collection-wildlife-25", "collection-wildlife-50"])
        XCTAssertEqual(CollectionProgress(category: .treasures, found: 0, total: 8).milestoneRewards, [])
    }
}
