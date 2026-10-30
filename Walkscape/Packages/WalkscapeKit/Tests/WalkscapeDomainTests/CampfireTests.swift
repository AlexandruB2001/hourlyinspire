import XCTest
@testable import WalkscapeDomain

final class CampfireTests: XCTestCase {
    func testLevelsNeedDistanceAndExpeditions() {
        XCTAssertEqual(Campsite(teamMeters: 0, expeditions: 0, placed: []).level.level, 1)
        XCTAssertEqual(Campsite(teamMeters: 60_000, expeditions: 0, placed: []).level.level, 1, "an expedition is needed too")
        XCTAssertEqual(Campsite(teamMeters: 60_000, expeditions: 1, placed: []).level.level, 2)
        XCTAssertEqual(Campsite(teamMeters: 2_000_000, expeditions: 5, placed: []).level.level, 5)
        XCTAssertNil(Campsite(teamMeters: 2_000_000, expeditions: 5, placed: []).nextLevel)
        let halfway = Campsite(teamMeters: 100_000, expeditions: 1, placed: [])
        XCTAssertEqual(halfway.fractionToNext, 0.5, accuracy: 0.001)
        let levels = CampfireCatalog.levels
        XCTAssertEqual(levels.map(\.level), [1, 2, 3, 4, 5])
        XCTAssertEqual(levels.map(\.meters), levels.map(\.meters).sorted())
    }

    func testOnlyUnlockedDecorationsShow() {
        let site = Campsite(teamMeters: 60_000, expeditions: 1, placed: ["lantern", "banner", "lantern", "nope", "flowers"])
        XCTAssertEqual(site.decorations, ["lantern", "flowers"])
        let many = CampfireCatalog.decorations.map(\.id)
        XCTAssertEqual(Campsite(teamMeters: 2_000_000, expeditions: 9, placed: many).decorations.count, CampfireCatalog.maxPlaced)
        for decoration in CampfireCatalog.decorations {
            XCTAssertNotNil(decoration.id.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression))
        }
    }

    func testLevelRewardsArePerPlayerNotPerTeam() {
        let site = Campsite(teamMeters: 200_000, expeditions: 2, placed: [])
        XCTAssertEqual(site.rewards.map(\.id), ["campfire-level-2", "campfire-level-3"])
        var ledger = RewardLedger()
        var wallet = WalletState()
        for reward in site.rewards { XCTAssertTrue(ledger.claim(reward, into: &wallet)) }
        // A different team at the same level pays nothing more.
        for reward in Campsite(teamMeters: 500_000, expeditions: 2, placed: []).rewards {
            XCTAssertFalse(ledger.claim(reward, into: &wallet))
        }
    }
}
