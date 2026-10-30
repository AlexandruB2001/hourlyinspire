import XCTest
@testable import WalkscapeDomain

final class TitleTests: XCTestCase {
    let engine = ZoneProgressionEngine()
    let day = LocalDay(year: 2026, month: 10, day: 30)

    func facts(meters: Int = 0, days: Int = 1, level: Int = 1, ledger: RewardLedger = RewardLedger(),
               companionStage: Int? = nil) -> ProfileFacts {
        var state = ProgressionState()
        for offset in 0..<days {
            _ = state.apply(DailyProgress(userID: "me", localDate: day.adding(days: offset), timeZoneIdentifier: "UTC",
                                          steps: meters, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date()),
                            using: engine)
        }
        return ProfileFacts(progression: state, explorerLevel: level, ledger: ledger, journal: JourneyJournal(),
                            companionStage: companionStage)
    }

    func testCatalogIdsAreUniqueAndValidForTheServer() {
        for ids in [TitleCatalog.all.map(\.id), FrameCatalog.all.map(\.id)] {
            XCTAssertEqual(Set(ids).count, ids.count)
            for id in ids { XCTAssertNotNil(id.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression), id) }
        }
        XCTAssertTrue(TitleCatalog.title(withID: TitleCatalog.defaultID)!.requirement.isMet(by: facts()))
    }

    func testTitlesUnlockFromProgress() {
        let newbie = facts()
        XCTAssertFalse(TitleCatalog.title(withID: "trailblazer")!.requirement.isMet(by: newbie))
        let walker = facts(meters: 10_500, days: 7, level: 10)
        for id in ["trailblazer", "summiteer", "rambler", "seasoned-explorer", "collector"] {
            XCTAssertTrue(TitleCatalog.title(withID: id)!.requirement.isMet(by: walker), id)
        }
        XCTAssertFalse(TitleCatalog.title(withID: "master-explorer")!.requirement.isMet(by: walker))
        XCTAssertFalse(TitleCatalog.title(withID: "forest-guardian")!.requirement.isMet(by: walker), "Maple Woods is at km 12")
    }

    func testQuestTitlesCountClaimedQuestsNotChests() {
        var ledger = RewardLedger()
        var wallet = WalletState()
        ledger.claim(Reward(id: "quest-week-chest-2026-10-26"), into: &wallet)
        XCTAssertTrue(TitleCatalog.title(withID: "weekly-champion")!.requirement.isMet(by: facts(ledger: ledger)))
        XCTAssertEqual(facts(ledger: ledger).questsClaimed, 0)
        for i in 0..<20 { ledger.claim(Reward(id: "quest-daily-2026-10-\(i)-walk"), into: &wallet) }
        XCTAssertTrue(TitleCatalog.title(withID: "questkeeper")!.requirement.isMet(by: facts(ledger: ledger)))
    }

    func testShowcaseFallsBackWhenSomethingIsLocked() {
        let showcase = ProfileShowcase(titleID: "master-explorer", frameID: "gold", favoriteZoneID: "summit",
                                       achievementIDs: ["first-steps", "curator"])
        let validated = showcase.validated(with: facts(meters: 1_200))
        XCTAssertEqual(validated.titleID, TitleCatalog.defaultID)
        XCTAssertEqual(validated.frameID, FrameCatalog.defaultID)
        XCTAssertNil(validated.favoriteZoneID, "the Summit isn't discovered yet")
        XCTAssertEqual(validated.achievementIDs, ["first-steps"])
        XCTAssertEqual(ProfileShowcase(frameID: "no-such-frame").validated(with: facts()).frameID, FrameCatalog.defaultID)
    }

    func testAtMostThreeShowcasedAchievements() {
        var showcase = ProfileShowcase()
        for id in ["a", "b", "c", "d"] { showcase.toggleAchievement(id) }
        XCTAssertEqual(showcase.achievementIDs, ["a", "b", "c"])
        showcase.toggleAchievement("b")
        XCTAssertEqual(showcase.achievementIDs, ["a", "c"])
    }

    func testOldSavesDecodeWithDefaults() throws {
        let decoded = try JSONDecoder().decode(ProfileShowcase.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, ProfileShowcase())
        XCTAssertNil(PublicShowcase(userID: "u", titleID: "from-the-future", frameID: nil, favoriteZoneID: nil).titleName)
    }
}
