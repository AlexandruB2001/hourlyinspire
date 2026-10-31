import XCTest
@testable import WalkscapeDomain

final class ExplorerTests: XCTestCase {
    let engine = ZoneProgressionEngine()
    let day1 = LocalDay(year: 2026, month: 10, day: 26)
    let day2 = LocalDay(year: 2026, month: 10, day: 27)

    func progress(_ meters: Int, on day: LocalDay) -> DailyProgress {
        DailyProgress(userID: "me", localDate: day, timeZoneIdentifier: "Europe/London",
                      steps: meters, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date())
    }

    func state(_ days: [(LocalDay, Int)]) -> ProgressionState {
        var state = ProgressionState()
        for (day, meters) in days { _ = state.apply(progress(meters, on: day), using: engine) }
        return state
    }

    // MARK: Level curve

    func testEarlyLevelsComeQuicklyAndLaterOnesSlowly() {
        XCTAssertEqual(ExplorerLevel.xpToAdvance(from: 1), 100)
        XCTAssertEqual(ExplorerLevel.xpToAdvance(from: 2), 280)
        XCTAssertEqual(ExplorerLevel.xpToAdvance(from: 4), 800)
        for level in 1..<99 {
            XCTAssertLessThan(ExplorerLevel.xpToAdvance(from: level), ExplorerLevel.xpToAdvance(from: level + 1))
        }
        // Roughly: level 10 after a few weeks of 5 km days, level 30 after about a year.
        XCTAssertLessThan(ExplorerLevel.totalXP(toReach: 10), 15_000)
        XCTAssertGreaterThan(ExplorerLevel.totalXP(toReach: 30), 150_000)
    }

    func testLevelBoundaries() {
        XCTAssertEqual(ExplorerLevel(totalXP: 0).level, 1)
        XCTAssertEqual(ExplorerLevel(totalXP: 99).level, 1)
        let two = ExplorerLevel(totalXP: 100)
        XCTAssertEqual(two.level, 2)
        XCTAssertEqual(two.xpIntoLevel, 0)
        XCTAssertEqual(two.xpForNextLevel, 280)
        XCTAssertEqual(ExplorerLevel(totalXP: 379).level, 2)
        XCTAssertEqual(ExplorerLevel(totalXP: 380).level, 3)
        XCTAssertEqual(ExplorerLevel(totalXP: -5).totalXP, 0)
        let max = ExplorerLevel(totalXP: Int.max / 2)
        XCTAssertEqual(max.level, 100)
        XCTAssertNil(max.xpForNextLevel)
        XCTAssertEqual(max.fraction, 1)
    }

    // MARK: XP sources

    func testXPComesFromWalkingDiscoveriesAndAchievements() {
        let xp = ExplorerXP(progression: state([(day1, 2_500)]), ledger: RewardLedger())
        XCTAssertEqual(xp.walking, 250)
        XCTAssertEqual(xp.zones, 3 * 50)         // Meadow, Riverside, Pine Forest
        XCTAssertEqual(xp.relics, 3 * 75)
        XCTAssertEqual(xp.achievements, 100)     // First Steps
        XCTAssertEqual(xp.total, 250 + 150 + 225 + 100)
    }

    func testRefreshesAndDownwardRevisionsNeverAddXP() {
        var progression = state([(day1, 4_000)])
        let before = ExplorerXP(progression: progression, ledger: RewardLedger()).total
        _ = progression.apply(progress(4_000, on: day1), using: engine)
        _ = progression.apply(progress(3_000, on: day1), using: engine)
        XCTAssertEqual(ExplorerXP(progression: progression, ledger: RewardLedger()).total, before)
    }

    // MARK: Ledger

    func testRewardsAreClaimedOnce() {
        var ledger = RewardLedger()
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        let reward = Reward(id: "quest-2026-10-26-steps", coins: 20, xp: 40, itemIDs: ["straw-hat"])
        XCTAssertTrue(ledger.claim(reward, into: &wallet))
        XCTAssertFalse(ledger.claim(reward, into: &wallet))
        XCTAssertEqual(wallet.coins, 20)
        XCTAssertEqual(ledger.rewardXP, 40)
        XCTAssertTrue(wallet.ownedItemIDs.contains("straw-hat"))
    }

    func testLevelUpsPayOnceEach() {
        var ledger = RewardLedger()
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        XCTAssertEqual(ledger.levelUps(totalXP: 50, into: &wallet), [])
        XCTAssertEqual(ledger.levelUps(totalXP: 400, into: &wallet), [2, 3])
        XCTAssertEqual(ledger.levelUps(totalXP: 400, into: &wallet), [])
        XCTAssertEqual(wallet.coins, 50)
        // Level rewards carry no XP, so they can't push the level further.
        XCTAssertEqual(ledger.rewardXP, 0)
    }

    func testOldLedgerDataDecodes() throws {
        let ledger = try JSONDecoder().decode(RewardLedger.self, from: Data("{}".utf8))
        XCTAssertEqual(ledger, RewardLedger())
    }

    // MARK: Cloud save merge

    func testMergingTwoPhonesLosesNothing() {
        var phoneA = WalletState(rules: CoinRules(starterCoins: 50))
        var ledgerA = RewardLedger()
        ledgerA.claim(Reward(id: "a", coins: 100, xp: 10), into: &phoneA)     // earned 150 total
        var generator = SeededGenerator(state: 5)
        _ = phoneA.openMysteryBox(from: [.outfit(ShopCatalog.item(withID: "straw-hat")!)], price: 100,
                                  using: &generator)                             // spent 100 → 50 left

        var phoneB = WalletState(rules: CoinRules(starterCoins: 50))
        var ledgerB = RewardLedger()
        ledgerB.claim(Reward(id: "b", coins: 250, xp: 20), into: &phoneB)     // earned 300, spent 0

        let merged = phoneA.merged(with: phoneB)
        XCTAssertEqual(merged.lifetimeCoins, 400, "both rewards count, the starter coins once")
        XCTAssertEqual(merged.coins, 300)
        XCTAssertTrue(merged.ownedItemIDs.contains("straw-hat"))
        XCTAssertEqual(merged.merged(with: phoneB), merged, "merging again changes nothing")

        let ledger = ledgerA.merged(with: ledgerB)
        XCTAssertTrue(ledger.hasClaimed("a") && ledger.hasClaimed("b"))
        XCTAssertEqual(ledger.rewardXP, 30)
    }

    func testProgressionMergeKeepsBestDaysAndAllDiscoveries() {
        let a = state([(day1, 3_000)])
        let b = state([(day1, 1_500), (day2, 6_000)])
        let merged = a.merged(with: b)
        XCTAssertEqual(merged.dailyBestMeters[day1.isoString], 3_000)
        XCTAssertEqual(merged.dailyBestMeters[day2.isoString], 6_000)
        XCTAssertEqual(merged.day, day2)
        XCTAssertEqual(merged.todayBestMeters, 6_000)
        XCTAssertEqual(merged.discoveredZoneIDs, b.discoveredZoneIDs.union(a.discoveredZoneIDs))
        XCTAssertEqual(merged.lifetimeMeters, 9_000)
        XCTAssertEqual(b.merged(with: a).lifetimeMeters, 9_000, "merge order doesn't matter for history")
    }

    func testANewPhoneTakesOverTheCloudSave() {
        let old = CloudSave(progression: state([(day1, 5_000)]), wallet: WalletState(), journal: JourneyJournal(),
                            ledger: RewardLedger(), companion: CompanionState(speciesID: "emberfox", adoptedOn: day1, lifetimeMeters: 0),
                            savedAt: Date(timeIntervalSince1970: 100))
        let fresh = CloudSave(progression: ProgressionState(), wallet: WalletState(), journal: JourneyJournal(),
                              ledger: RewardLedger(), companion: CompanionState(speciesID: "mossling", adoptedOn: day2, lifetimeMeters: 0),
                              savedAt: Date(timeIntervalSince1970: 200))
        let merged = fresh.merged(with: old)
        XCTAssertEqual(merged.progression.lifetimeMeters, 5_000)
        XCTAssertEqual(merged.companion?.speciesID, "emberfox", "the companion adopted first is kept")
        XCTAssertEqual(merged.savedAt, Date(timeIntervalSince1970: 200))
    }

    func testCloudSaveRoundTrips() throws {
        let save = CloudSave(progression: state([(day1, 2_000)]), wallet: WalletState(), journal: JourneyJournal(),
                             ledger: RewardLedger(), companion: nil, savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try JSONDecoder().decode(CloudSave.self, from: JSONEncoder().encode(save))
        XCTAssertEqual(decoded, save)
    }

    func testEveryKilometreEarnsXPWithNoDailyCap() {
        for meters in [5_000, 25_000, 42_195, 60_000, 100_000] {
            let xp = ExplorerXP(progression: state([(day1, meters)]), ledger: RewardLedger(), achievements: [])
            XCTAssertEqual(xp.walking, meters * ExplorerRules.standard.xpPerKilometre / 1_000, "\(meters) m")
        }
        let week = state([(day1, 42_195), (day2, 60_000)])
        XCTAssertEqual(ExplorerXP(progression: week, ledger: RewardLedger(), achievements: []).walking, 10_219,
                       "days add up in full")
    }
}
