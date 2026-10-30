import XCTest
@testable import WalkscapeDomain

/// Deterministic generator so mystery-box rolls are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class WalletTests: XCTestCase {
    let today = LocalDay(year: 2026, month: 10, day: 27)

    func progress(_ meters: Int, day: LocalDay? = nil) -> DailyProgress {
        DailyProgress(userID: "me", localDate: day ?? today, timeZoneIdentifier: "Europe/London",
                      steps: meters, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date())
    }

    /// A wallet with `coins` to spend and no chests.
    func wallet(coins: Int) -> WalletState {
        WalletState(rules: CoinRules(starterCoins: coins))
    }

    // MARK: Catalog

    func testCatalogHasThirtyUniqueItemsAcrossRarities() {
        let items = ShopCatalog.items
        XCTAssertEqual(items.count, 30)
        XCTAssertEqual(Set(items.map(\.id)).count, 30)
        let counts = Dictionary(grouping: items, by: \.rarity).mapValues(\.count)
        XCTAssertEqual(counts, [.common: 12, .rare: 9, .epic: 6, .legendary: 3])
        XCTAssertEqual(Set(items.map(\.slot)), Set(EquipmentSlot.allCases))
        XCTAssertEqual(ShopCatalog.item(withID: "straw-hat")?.price, 100)
        XCTAssertEqual(Rarity.allCases.map(\.mysteryBoxWeight).reduce(0, +), 100)
        XCTAssertLessThan(Rarity.rare, Rarity.legendary)
    }

    // MARK: Earning

    func testNewWalletHasStarterCoins() {
        XCTAssertEqual(WalletState().coins, 50)
    }

    func testKilometreMilestonesPayOncePerDay() {
        var wallet = wallet(coins: 0)
        XCTAssertEqual(wallet.apply(progress(999)).coinsEarned, 0)
        XCTAssertEqual(wallet.apply(progress(1_000)).coinsEarned, 10)
        XCTAssertEqual(wallet.apply(progress(1_000)).coinsEarned, 0)
        XCTAssertEqual(wallet.apply(progress(800)).coinsEarned, 0, "a revised-down total never pays")
        XCTAssertEqual(wallet.apply(progress(3_400)).coinsEarned, 20, "two milestones in one update")
        XCTAssertEqual(wallet.coins, 30)

        // A new day pays again from the first kilometre.
        XCTAssertEqual(wallet.apply(progress(1_500, day: today.adding(days: 1))).coinsEarned, 10)
        XCTAssertEqual(wallet.coins, 40)
        XCTAssertEqual(wallet.lifetimeCoins, 40)
    }

    func testLateUpdateForEarlierDayPaysNothing() {
        var wallet = wallet(coins: 0)
        _ = wallet.apply(progress(500))
        let event = wallet.apply(progress(8_000, day: today.adding(days: -1)))
        XCTAssertEqual(event, WalletEvent.none)
        XCTAssertEqual(wallet.coins, 0)
        XCTAssertEqual(wallet.day, today)
    }

    func testChestsSitInsideTheirSegmentAndAreStable() {
        for index in 0..<40 {
            let meters = WalletState.chestMeters(index: index, on: today)
            XCTAssertTrue((index * 500 + 50..<index * 500 + 450).contains(meters), "chest \(index) at \(meters)")
            XCTAssertEqual(meters, WalletState.chestMeters(index: index, on: today))
        }
        XCTAssertNotEqual((0..<10).map { WalletState.chestMeters(index: $0, on: today) },
                          (0..<10).map { WalletState.chestMeters(index: $0, on: today.adding(days: 1)) },
                          "each day hides its chests in new places")
    }

    func testChestsAppearAsYouWalkAndOpenForFiveCoins() {
        var wallet = wallet(coins: 0)
        XCTAssertEqual(wallet.apply(progress(0)).newChests, 0)
        XCTAssertEqual(wallet.apply(progress(1_000)).newChests, 2, "two chests per kilometre")
        XCTAssertEqual(wallet.apply(progress(1_000)).newChests, 0)
        let first = WalletState.chestMeters(index: 2, on: today)
        XCTAssertEqual(wallet.apply(progress(first - 1)).newChests, 0)
        XCTAssertEqual(wallet.apply(progress(first)).newChests, 1)
        XCTAssertEqual(wallet.pendingChests, 3)

        let coinsBefore = wallet.coins
        XCTAssertEqual(wallet.openChest(), 5)
        XCTAssertEqual(wallet.coins, coinsBefore + 5)
        XCTAssertEqual(wallet.pendingChests, 2)
        _ = wallet.openChest()
        _ = wallet.openChest()
        XCTAssertNil(wallet.openChest())

        // Unopened chests wait overnight; new ones keep counting from zero each day.
        _ = wallet.apply(progress(2_000))
        XCTAssertEqual(wallet.apply(progress(600, day: today.adding(days: 1))).newChests,
                       WalletState.chestsReached(meters: 600, on: today.adding(days: 1)))
        XCTAssertGreaterThanOrEqual(wallet.pendingChests, 1)
    }

    func testHugeDistancesDoNotHang() {
        XCTAssertEqual(WalletState.chestsReached(meters: 1_000_000_000, on: today), 2_000_000)
    }

    // MARK: Shopping

    func testBuyingDeductsCoinsAndCanOnlyHappenOnce() {
        var wallet = wallet(coins: 250)
        let hat = ShopCatalog.item(withID: "straw-hat")!
        let crown = ShopCatalog.item(withID: "golden-crown")!
        XCTAssertEqual(wallet.buy(crown), .notEnoughCoins(needed: 350))
        XCTAssertEqual(wallet.buy(hat), .purchased(hat))
        XCTAssertEqual(wallet.coins, 150)
        XCTAssertEqual(wallet.buy(hat), .alreadyOwned)
        XCTAssertEqual(wallet.coins, 150)
    }

    func testMysteryBoxOnlyGivesNewItemsUntilSoldOut() {
        var wallet = wallet(coins: 50 * 31)
        var generator = SeededGenerator(state: 42)
        var won = Set<String>()
        for _ in 0..<30 {
            guard case .purchased(let item) = wallet.openMysteryBox(using: &generator) else {
                return XCTFail("expected an item")
            }
            XCTAssertTrue(won.insert(item.id).inserted, "duplicate \(item.id)")
        }
        XCTAssertEqual(won.count, 30)
        XCTAssertEqual(wallet.openMysteryBox(using: &generator), .soldOut)
        XCTAssertEqual(wallet.coins, 50, "a sold-out box costs nothing")
    }

    func testMysteryBoxNeedsFiftyCoins() {
        var wallet = wallet(coins: 49)
        var generator = SeededGenerator(state: 1)
        XCTAssertEqual(wallet.openMysteryBox(using: &generator), .notEnoughCoins(needed: 1))
        XCTAssertTrue(wallet.ownedItemIDs.isEmpty)
    }

    func testMysteryBoxOddsFollowRarity() {
        var generator = SeededGenerator(state: 7)
        var counts: [Rarity: Int] = [:]
        for _ in 0..<5_000 {
            var wallet = wallet(coins: 50)
            if case .purchased(let item) = wallet.openMysteryBox(using: &generator) { counts[item.rarity, default: 0] += 1 }
        }
        XCTAssertEqual(Double(counts[.common] ?? 0) / 5_000, 0.60, accuracy: 0.03)
        XCTAssertEqual(Double(counts[.rare] ?? 0) / 5_000, 0.28, accuracy: 0.03)
        XCTAssertEqual(Double(counts[.epic] ?? 0) / 5_000, 0.10, accuracy: 0.02)
        XCTAssertEqual(Double(counts[.legendary] ?? 0) / 5_000, 0.02, accuracy: 0.01)
    }

    // MARK: Outfit

    func testEquippingNeedsOwnershipAndReplacesTheSlot() {
        var wallet = wallet(coins: 1_000)
        let straw = ShopCatalog.item(withID: "straw-hat")!
        let beanie = ShopCatalog.item(withID: "red-beanie")!
        let boots = ShopCatalog.item(withID: "golden-boots")!
        XCTAssertFalse(wallet.equip(straw))
        _ = wallet.buy(straw)
        _ = wallet.buy(beanie)
        _ = wallet.buy(boots)
        XCTAssertTrue(wallet.equip(straw))
        XCTAssertTrue(wallet.equip(boots))
        XCTAssertTrue(wallet.equip(beanie))
        XCTAssertFalse(wallet.isEquipped(straw))
        XCTAssertEqual(wallet.outfit, ["red-beanie", "golden-boots"])
        wallet.unequip(.head)
        XCTAssertEqual(wallet.outfit, ["golden-boots"])
    }

    func testWalletRoundTripsThroughJSON() throws {
        var wallet = wallet(coins: 500)
        _ = wallet.apply(progress(2_600))
        _ = wallet.buy(ShopCatalog.item(withID: "sunglasses")!)
        wallet.equip(ShopCatalog.item(withID: "sunglasses")!)
        let decoded = try JSONDecoder().decode(WalletState.self, from: JSONEncoder().encode(wallet))
        XCTAssertEqual(decoded, wallet)
    }

    // MARK: Two phones

    func testSpendingOnTwoPhonesIsNeverRefunded() {
        var phoneA = wallet(coins: 300)
        var phoneB = phoneA
        XCTAssertEqual(phoneA.buy(ShopCatalog.item(withID: "straw-hat")!), .purchased(ShopCatalog.item(withID: "straw-hat")!))
        XCTAssertTrue(phoneB.buy(itemID: "pet-straw-hat", price: 120))
        let merged = phoneA.merged(with: phoneB)
        XCTAssertEqual(merged.spentCoins, phoneA.spentCoins + phoneB.spentCoins, "both purchases are paid for")
        XCTAssertEqual(merged.coins, 300 - phoneA.spentCoins - 120)
        XCTAssertEqual(merged, phoneB.merged(with: phoneA), "merge order doesn't matter")
        XCTAssertEqual(merged.merged(with: phoneA), merged, "merging again changes nothing")
    }

    func testTheSameEarningOnTwoPhonesCountsOnce() {
        var phoneA = wallet(coins: 0)
        var phoneB = wallet(coins: 0)
        _ = phoneA.apply(progress(3_200))
        _ = phoneB.apply(progress(4_100))
        var ledgerA = RewardLedger()
        var ledgerB = RewardLedger()
        ledgerA.claim(Reward(id: "quest-1", coins: 30), into: &phoneA)
        ledgerB.claim(Reward(id: "quest-1", coins: 30), into: &phoneB)
        phoneA.earnAdReward(15, id: "view-a")
        phoneB.earnAdReward(15, id: "view-b")
        let merged = phoneA.merged(with: phoneB)
        XCTAssertEqual(merged.lifetimeCoins, 40 + 30 + 15 + 15, "today's walk and the quest once; both ads")
        XCTAssertEqual(merged.coins, merged.lifetimeCoins)
    }

    func testChestsOpenedOnEitherPhoneArePaidOnce() {
        var phoneA = wallet(coins: 0)
        _ = phoneA.apply(progress(1_000))
        var phoneB = phoneA
        XCTAssertEqual(phoneA.pendingChests, 2)
        XCTAssertEqual(phoneA.openChest(), 5)
        XCTAssertEqual(phoneB.openChest(), 5)
        let merged = phoneA.merged(with: phoneB)
        XCTAssertEqual(merged.pendingChests, 1, "the same chest opened on both phones")
        XCTAssertEqual(merged.coins, 10 + 5)
    }

    func testOlderSavesKeepTheirCoinsAndChests() throws {
        let saved = """
        {"coins":180,"lifetimeCoins":420,"ownedItemIDs":["straw-hat"],"equipped":{"head":"straw-hat"},
         "pendingChests":2,"day":"2026-10-27","kilometresRewardedToday":3,"chestsFoundToday":6}
        """
        var old = try JSONDecoder().decode(WalletState.self, from: Data(saved.utf8))
        XCTAssertEqual(old.coins, 180)
        XCTAssertEqual(old.pendingChests, 2)
        let before = old.coins
        _ = old.apply(progress(3_500))
        XCTAssertEqual(old.coins, before, "kilometres already paid today aren't paid again")
        _ = old.apply(progress(4_000))
        XCTAssertEqual(old.coins, before + 10, "the next kilometre is")
        // A brand-new phone merging with the older save doesn't add its starter coins on top.
        let merged = WalletState().merged(with: try JSONDecoder().decode(WalletState.self, from: Data(saved.utf8)))
        XCTAssertEqual(merged.coins, 180)
        // Round trip.
        XCTAssertEqual(try JSONDecoder().decode(WalletState.self, from: JSONEncoder().encode(old)), old)
    }

    func testTwoOlderSavesFromDifferentDaysDontCountADayTwice() throws {
        func save(coins: Int, lifetime: Int, day: String, km: Int) -> Data {
            Data("""
            {"coins":\(coins),"lifetimeCoins":\(lifetime),"ownedItemIDs":[],"equipped":{},
             "pendingChests":0,"day":"\(day)","kilometresRewardedToday":\(km),"chestsFoundToday":0}
            """.utf8)
        }
        // The cloud save is from yesterday; this phone has walked on since and includes it.
        let cloud = try JSONDecoder().decode(WalletState.self, from: save(coins: 300, lifetime: 500, day: "2026-10-26", km: 5))
        let phone = try JSONDecoder().decode(WalletState.self, from: save(coins: 340, lifetime: 540, day: "2026-10-27", km: 4))
        XCTAssertEqual(phone.merged(with: cloud).coins, 340)
        XCTAssertEqual(phone.merged(with: cloud).lifetimeCoins - phone.merged(with: cloud).spentCoins, 340)
    }
}
