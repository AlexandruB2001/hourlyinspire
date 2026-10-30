import XCTest
@testable import WalkscapeDomain

/// Regression tests for the "four free chests on every launch" exploit: the
/// cloud-save merge used to keep the larger waiting-chest count, so a stale
/// cloud copy brought opened chests back on every sync.
final class ChestTests: XCTestCase {
    let today = LocalDay(year: 2026, month: 10, day: 30)

    func progress(_ meters: Int, day: LocalDay? = nil) -> DailyProgress {
        DailyProgress(userID: "me", localDate: day ?? today, timeZoneIdentifier: "Europe/London",
                      steps: meters, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date())
    }

    /// What a launch does to the wallet: load it from disk, then apply today's Health totals.
    func relaunch(_ wallet: WalletState, walked meters: Int) throws -> WalletState {
        var loaded = try JSONDecoder().decode(WalletState.self, from: JSONEncoder().encode(wallet))
        _ = loaded.apply(progress(meters))
        return loaded
    }

    func testOpeningTheAppRepeatedlyAddsNoChests() throws {
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        _ = wallet.apply(progress(2_000))
        let ids = wallet.pendingChestIDs
        XCTAssertEqual(ids.count, 4)
        for _ in 0..<10 { wallet = try relaunch(wallet, walked: 2_000) }
        XCTAssertEqual(wallet.pendingChestIDs, ids)
        while wallet.openChest() != nil {}
        for _ in 0..<10 { wallet = try relaunch(wallet, walked: 2_000) }
        XCTAssertTrue(wallet.pendingChestIDs.isEmpty, "opened chests never come back")
        XCTAssertEqual(wallet.coins, 20 + 4 * 5)
    }

    func testRepeatedHealthSyncsDontDuplicateChests() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        for _ in 0..<5 { _ = wallet.apply(progress(1_500)) }
        XCTAssertEqual(wallet.pendingChests, 3)
        // A late, lower reading changes nothing either.
        _ = wallet.apply(progress(900))
        XCTAssertEqual(wallet.pendingChests, 3)
    }

    func testANewMilestoneAddsItsChest() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        _ = wallet.apply(progress(999))
        let before = wallet.pendingChestIDs
        let event = wallet.apply(progress(2_000))
        XCTAssertEqual(event.newChests, wallet.pendingChestIDs.count - before.count)
        XCTAssertTrue(wallet.pendingChestIDs.starts(with: before), "earlier chests keep their ids")
        XCTAssertEqual(wallet.pendingChestIDs.last, WalletState.chestID(day: today.isoString, index: wallet.chestsFoundToday - 1))
        // Chests stay tied to their own day.
        _ = wallet.apply(progress(600, day: today.adding(days: 1)))
        XCTAssertEqual(Set(wallet.pendingChestIDs.map { $0.components(separatedBy: "#")[0] }),
                       [today.isoString, today.adding(days: 1).isoString])
    }

    func testClaimingTheSameChestTwicePaysOnce() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        _ = wallet.apply(progress(1_000))
        let id = wallet.pendingChestIDs[0]
        XCTAssertEqual(wallet.openChest(id: id), 5)
        XCTAssertNil(wallet.openChest(id: id))
        XCTAssertNil(wallet.openChest(id: "\(today.isoString)#99"), "a chest that was never found")
        XCTAssertNil(wallet.openChest(id: "nonsense"))
        XCTAssertTrue(wallet.isChestOpened(id))
        XCTAssertEqual(wallet.coins, 10 + 5)
    }

    func testRestartingKeepsFoundAndOpenedChests() throws {
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        _ = wallet.apply(progress(1_600))
        _ = wallet.openChest()
        let restored = try JSONDecoder().decode(WalletState.self, from: JSONEncoder().encode(wallet))
        XCTAssertEqual(restored, wallet)
        XCTAssertEqual(restored.pendingChestIDs, wallet.pendingChestIDs)
        XCTAssertTrue(restored.isChestOpened(WalletState.chestID(day: today.isoString, index: 0)))
    }

    /// The exploit itself: open chests offline, then sync with a stale cloud
    /// copy that still has them waiting, launch after launch.
    func testSyncingWithAStaleCloudSaveNeverBringsChestsBack() throws {
        var phone = WalletState(rules: CoinRules(starterCoins: 0))
        _ = phone.apply(progress(2_000))
        var cloud = phone                                   // synced while the chests were waiting
        while phone.openChest() != nil {}                   // opened offline
        let coinsAfterOpening = phone.coins
        for _ in 0..<5 {
            phone = try relaunch(phone.merged(with: cloud), walked: 2_000)
            cloud = phone                                    // the merged save is stored back
            XCTAssertTrue(phone.pendingChestIDs.isEmpty)
            XCTAssertEqual(phone.coins, coinsAfterOpening)
        }
        // A second phone that opened the same chests doesn't double the coins either.
        var other = WalletState(rules: CoinRules(starterCoins: 0))
        _ = other.apply(progress(2_000))
        while other.openChest() != nil {}
        XCTAssertEqual(phone.merged(with: other).coins, coinsAfterOpening)
    }

    func testChestsWaitingInOlderSavesAreKept() throws {
        let saved = """
        {"coins":100,"lifetimeCoins":300,"ownedItemIDs":[],"equipped":{},
         "pendingChests":3,"day":"2026-10-29","kilometresRewardedToday":2,"chestsFoundToday":4}
        """
        var wallet = try JSONDecoder().decode(WalletState.self, from: Data(saved.utf8))
        XCTAssertEqual(wallet.coins, 100)
        XCTAssertEqual(wallet.pendingChests, 3)
        XCTAssertEqual(wallet.pendingChestIDs, ["legacy#0", "legacy#1", "legacy#2"])
        _ = wallet.openChest()
        let stale = try JSONDecoder().decode(WalletState.self, from: Data(saved.utf8))
        let merged = wallet.merged(with: stale)
        XCTAssertEqual(merged.pendingChests, 2, "the opened one stays opened")
        XCTAssertEqual(merged.coins, 105)
    }
}
