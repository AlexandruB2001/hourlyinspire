import XCTest
@testable import WalkscapeDomain

/// The server sells Mystery Boxes and adoptions from its own copy of the
/// prices and prize pool (migration 20261110000001). These keep it in step.
final class ServerWalletCatalogTests: XCTestCase {
    func migration() throws -> String {
        // Walk up from this file to the folder that holds supabase/.
        var folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.appendingPathComponent("supabase").path), folder.pathComponents.count > 1 {
            folder.deleteLastPathComponent()
        }
        return try String(contentsOf: folder.appendingPathComponent("supabase/migrations/20261110000001_server_wallet_spending.sql"),
                          encoding: .utf8)
    }

    func festivalWindow(of itemID: String) -> String {
        guard let event = SeasonalEventCatalog.all.first(where: { $0.tiers.contains { $0.itemIDs.contains(itemID) } }) else {
            return "null, null"
        }
        return "\(event.start.month * 100 + event.start.day), \(event.end.month * 100 + event.end.day)"
    }

    func testServerPrizePoolMatchesTheApp() throws {
        let sql = try migration()
        var rows = 0
        for item in ShopCatalog.items {
            XCTAssertTrue(sql.contains("('\(item.id)', 'outfit', '\(item.rarity.rawValue)', null, null)"), item.id)
            rows += 1
        }
        for accessory in CompanionAccessoryCatalog.all {
            guard let rarity = accessory.rarity else { continue }
            XCTAssertTrue(sql.contains("('\(accessory.id)', 'accessory', '\(rarity.rawValue)', \(festivalWindow(of: accessory.id)))"),
                          accessory.id)
            rows += 1
        }
        let serverRows = sql.components(separatedBy: "', 'outfit', '").count - 1 + sql.components(separatedBy: "', 'accessory', '").count - 1
        XCTAssertEqual(serverRows, rows, "no extra prizes on the server")
    }

    func testServerPricesWeightsAndCompanionsMatchTheApp() throws {
        let sql = try migration()
        XCTAssertTrue(sql.contains("('mystery-box', \(ShopCatalog.mysteryBoxPrice))"))
        XCTAssertTrue(sql.contains("('companion-adoption', \(CompanionRoster.adoptionCost))"))
        XCTAssertTrue(sql.contains("('rewarded-ad', \(AdRules.standard.rewardedCoins))"))
        for rarity in Rarity.allCases where rarity != .legendary {
            XCTAssertTrue(sql.contains("when '\(rarity.rawValue)' then \(rarity.mysteryBoxWeight)"), rarity.rawValue)
        }
        XCTAssertTrue(sql.contains("else \(Rarity.legendary.mysteryBoxWeight) end"))
        let species = CompanionCatalog.starters.map { "'\($0.id)'" }.joined(separator: ", ")
        XCTAssertTrue(sql.contains("not in (\(species))"), "the server knows every companion")
        XCTAssertEqual(CompanionRoster.adoptionChargeKey("emberfox"), "companion-emberfox", "the server charges under the app's key")
    }

    func testAServerPurchaseLandsInTheWalletOnce() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 400))
        wallet.receiveServerPurchase(chargeKey: "box-1", coins: 150, itemID: "golden-crown")
        wallet.receiveServerPurchase(chargeKey: "box-1", coins: 150, itemID: "golden-crown")
        XCTAssertEqual(wallet.coins, 250)
        XCTAssertTrue(wallet.owns(itemID: "golden-crown"))
        XCTAssertEqual(MysteryBox.prize(withID: "golden-crown")?.id, "golden-crown")
        XCTAssertEqual(MysteryBox.prize(withID: "pet-snow-hat")?.id, "pet-snow-hat", "festival prizes are found any day")
        XCTAssertNil(MysteryBox.prize(withID: "pet-bow"), "level gifts aren't box prizes")
    }
}
