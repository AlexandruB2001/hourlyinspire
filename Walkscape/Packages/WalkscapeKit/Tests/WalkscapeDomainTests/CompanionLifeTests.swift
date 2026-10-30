import XCTest
@testable import WalkscapeDomain

final class CompanionLifeTests: XCTestCase {
    let start = LocalDay(year: 2026, month: 11, day: 1)

    func testEachCompanionHasItsOwnKindOfFind() {
        XCTAssertEqual(CompanionPersonality.findKind(for: "mossling"), .minerals)
        XCTAssertEqual(CompanionPersonality.findKind(for: "emberfox"), .treasure)
        XCTAssertEqual(CompanionPersonality.findKind(for: "moonmoth"), .nightlife)
    }

    func testFindsAreFixedPerDayAndNeedAWalk() {
        for species in CompanionCatalog.starters.map(\.id) {
            var found = 0
            for offset in 0..<200 {
                let day = start.adding(days: offset)
                let find = CompanionPersonality.find(speciesID: species, day: day, metersToday: 2_000,
                                                     ownedTreasures: [], seenCreatures: [])
                XCTAssertEqual(find, CompanionPersonality.find(speciesID: species, day: day, metersToday: 2_000,
                                                               ownedTreasures: [], seenCreatures: []))
                XCTAssertNil(CompanionPersonality.find(speciesID: species, day: day, metersToday: 500,
                                                       ownedTreasures: [], seenCreatures: []), "no walk, no find")
                if let find {
                    found += 1
                    XCTAssertEqual(find.reward.id, "companion-find-\(day.isoString)")
                    if species == "mossling", let treasure = find.treasure {
                        XCTAssertTrue(["amber", "ruby", "pearl"].contains(treasure.id), "Mossling finds stones")
                    }
                    if let creature = find.creature { XCTAssertEqual(species, "moonmoth") ; XCTAssertNotNil(WildlifeCatalog.creature(withID: creature.id)) }
                }
            }
            XCTAssertEqual(Double(found) / 200, CompanionPersonality.dailyFindChance, accuracy: 0.1, species)
        }
    }

    func testMoonmothOnlyLeadsYouToCreaturesYouHaventSeen() {
        let seen: Set<String> = ["owl", "deer", "aurora-moth", "firefly-sprite", "bat", "wisp"]
        for offset in 0..<300 {
            let find = CompanionPersonality.find(speciesID: "moonmoth", day: start.adding(days: offset), metersToday: 3_000,
                                                 ownedTreasures: [], seenCreatures: seen)
            XCTAssertNil(find?.creature)
        }
    }

    func testVoiceLinesFitThePersonality() {
        let line = CompanionVoice.line(speciesID: "emberfox", situation: .newZone("Riverside"), day: start)
        XCTAssertEqual(line, "Emberfox races into Riverside!")
        XCTAssertTrue(CompanionVoice.line(speciesID: "mossling", situation: .levelUp(7), day: start).contains("7"))
        XCTAssertEqual(CompanionVoice.line(speciesID: "nobody", situation: .walking, day: start), "")
    }

    func testAccessoriesToggleOnePerSlot() throws {
        var companion = CompanionState(speciesID: "mossling", adoptedOn: start, lifetimeMeters: 0)
        let bow = try XCTUnwrap(CompanionAccessoryCatalog.accessory(withID: "pet-bow"))
        let hat = try XCTUnwrap(CompanionAccessoryCatalog.accessory(withID: "pet-straw-hat"))
        let scarf = try XCTUnwrap(CompanionAccessoryCatalog.accessory(withID: "pet-red-scarf"))
        companion.toggle(bow)
        companion.toggle(scarf)
        companion.toggle(hat)
        XCTAssertEqual(companion.wornAccessories, ["pet-red-scarf", "pet-straw-hat"], "the hat replaces the bow")
        companion.toggle(hat)
        XCTAssertEqual(companion.wornAccessories, ["pet-red-scarf"])
        XCTAssertEqual(Set(CompanionAccessoryCatalog.all.map(\.id)).count, CompanionAccessoryCatalog.all.count)
        XCTAssertEqual(CompanionAccessoryCatalog.unlocked(atLevel: 5).map(\.id), ["pet-bow"])
    }

    func testOldCompanionSavesDecodeWithoutAccessories() throws {
        let json = #"{"speciesID":"emberfox","adoptedOn":"2026-10-30","baselineMeters":1200,"celebratedStage":1}"#
        let companion = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(companion.speciesID, "emberfox")
        XCTAssertEqual(companion.celebratedStage, 1)
        XCTAssertTrue(companion.wornAccessories.isEmpty)
        let again = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(companion))
        XCTAssertEqual(again, companion)
    }

    func testBuyingByIDSpendsCoinsOnce() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 150))
        XCTAssertTrue(wallet.buy(itemID: "pet-straw-hat", price: 120))
        XCTAssertFalse(wallet.buy(itemID: "pet-straw-hat", price: 120))
        XCTAssertFalse(wallet.buy(itemID: "pet-cape", price: 250), "not enough coins")
        XCTAssertEqual(wallet.coins, 30)
        XCTAssertTrue(wallet.owns(itemID: "pet-straw-hat"))
    }
}
