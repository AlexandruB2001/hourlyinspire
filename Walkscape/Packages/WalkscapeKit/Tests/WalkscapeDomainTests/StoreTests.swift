import XCTest
@testable import WalkscapeDomain

final class StoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCatalogMatchesTheApprovedProductsAndPrices() {
        XCTAssertEqual(StoreCatalog.plus.map(\.fallbackPrice), ["$2.99", "$19.99"])
        XCTAssertEqual(StoreCatalog.bundles.map(\.fallbackPrice), ["$2.99", "$1.99", "$0.99", "$1.99"])
        XCTAssertEqual(Set(StoreCatalog.allIDs).count, StoreCatalog.all.count)
        for product in StoreCatalog.all {
            XCTAssertTrue(product.id.hasPrefix("com.alexandrub.walkscape."), product.id)
            if product.kind == .bundle { XCTAssertFalse(product.contents.isEmpty, product.id) }
        }
    }

    func testNothingSoldAffectsGameplay() {
        // Bundles only contain cosmetics the game knows how to draw.
        let cosmetics = Set(PremiumOutfits.items.map(\.id) + CompanionSkinCatalog.all.map(\.id)
            + TrailEffectCatalog.all.map(\.id) + CampfireCatalog.premiumDecorations.map(\.id))
        for bundle in StoreCatalog.bundles {
            XCTAssertTrue(Set(bundle.contents).isSubset(of: cosmetics), bundle.id)
        }
        // Premium outfits never appear in the coin shop or the Mystery Box.
        XCTAssertTrue(Set(ShopCatalog.items.map(\.id)).isDisjoint(with: PremiumOutfits.items.map(\.id)))
        XCTAssertEqual(ShopCatalog.items.count, 45)
        XCTAssertEqual(ShopCatalog.item(withID: "harvest-crown")?.slot, .head, "premium pieces can still be worn")
    }

    func testEntitlements() {
        var entitlements = Entitlements()
        XCTAssertFalse(entitlements.hasPlus(at: now))
        XCTAssertFalse(entitlements.owns("skin-golden"))
        entitlements.bundles.insert(StoreCatalog.prefix + "bundle.companionskins")
        XCTAssertTrue(entitlements.owns("skin-golden"))
        XCTAssertFalse(entitlements.owns("trail-petals"))
        entitlements.plusExpires = now.addingTimeInterval(60)
        XCTAssertTrue(entitlements.hasPlus(at: now))
        XCTAssertFalse(entitlements.hasPlus(at: now.addingTimeInterval(120)), "Plus ends when the subscription lapses")
    }

    func testPlusGiftsRotateMonthlyAndPayOncePerMonth() {
        let october = LocalDay(year: 2026, month: 10, day: 30)
        let november = LocalDay(year: 2026, month: 11, day: 2)
        XCTAssertNotEqual(PlusMonthlyGift.itemID(for: october), PlusMonthlyGift.itemID(for: november))
        XCTAssertEqual(PlusMonthlyGift.reward(for: october).id, "plus-gift-2026-10")
        XCTAssertEqual(PlusMonthlyGift.reward(for: LocalDay(year: 2026, month: 10, day: 1)).id, "plus-gift-2026-10")
        for id in PlusMonthlyGift.rotation { XCTAssertNotNil(CompanionAccessoryCatalog.accessory(withID: id), id) }
        var ledger = RewardLedger()
        var wallet = WalletState()
        XCTAssertTrue(ledger.claim(PlusMonthlyGift.reward(for: october), into: &wallet))
        XCTAssertFalse(ledger.claim(PlusMonthlyGift.reward(for: october), into: &wallet))
        XCTAssertTrue(wallet.owns(itemID: PlusMonthlyGift.itemID(for: october)), "gifts are kept for good")
    }

    func testLooksFallBackWhenNoLongerOwned() {
        let look = PremiumLook(companionSkinID: "skin-frost", trailEffectID: "trail-stars", journalThemeID: "moonlight")
        let none = look.validated(entitlements: Entitlements(), now: now)
        XCTAssertNil(none.companionSkinID)
        XCTAssertNil(none.trailEffectID)
        XCTAssertEqual(none.journalThemeID, JournalThemeCatalog.defaultID)
        let all = Entitlements(bundles: Set(StoreCatalog.bundles.map(\.id)), plusExpires: now.addingTimeInterval(3600))
        XCTAssertEqual(look.validated(entitlements: all, now: now), look)
    }

    func testPlusFramesNeedPlus() {
        let facts = { (plus: Bool) in ProfileFacts(progression: ProgressionState(), explorerLevel: 1, ledger: RewardLedger(),
                                                   journal: JourneyJournal(), companionStage: nil, hasPlus: plus) }
        let prism = FrameCatalog.frame(withID: "prism")
        XCTAssertEqual(prism.id, "prism")
        XCTAssertFalse(prism.requirement.isMet(by: facts(false)))
        XCTAssertTrue(prism.requirement.isMet(by: facts(true)))
    }
}
