import XCTest
@testable import WalkscapeDomain

final class LookAndCompanionTests: XCTestCase {
    func testLooksRoundTripThroughTheAvatarID() {
        XCTAssertEqual(CharacterLook(avatarID: "fern").avatarID, "fern", "plain looks keep their old ids")
        let look = CharacterLook(colors: "plum", hair: .pigtails, body: .dress, skin: .four)
        XCTAssertEqual(look.avatarID, "plum-pigtails-dress-skin4")
        XCTAssertEqual(CharacterLook(avatarID: look.avatarID), look)
        XCTAssertEqual(CharacterLook(avatarID: "sky-bun").hair, .bun)
        XCTAssertEqual(CharacterLook(avatarID: "nonsense-wings-skin9").avatarID, "fern", "unknown parts are ignored")
        XCTAssertEqual(look.with(hair: .short).with(body: .trousers).with(skin: nil).avatarID, "plum")
    }

    func testEveryLookFitsTheServerAvatarFormat() {
        for avatar in AvatarCatalog.starters {
            for hair in HairStyle.allCases {
                for body in BodyStyle.allCases {
                    for skin in [nil] + SkinTone.allCases.map(Optional.some) {
                        let id = CharacterLook(colors: avatar.id, hair: hair, body: body, skin: skin).avatarID
                        XCTAssertNotNil(id.range(of: "^[a-z0-9_-]{1,32}$", options: .regularExpression), id)
                    }
                }
            }
        }
    }

    let day = LocalDay(year: 2026, month: 11, day: 1)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSwappingKeepsEachCompanionsGrowth() {
        var roster = CompanionRoster()
        let moss = CompanionState(speciesID: "mossling", adoptedOn: day, lifetimeMeters: 10_000)
        // Walk 7 km with Mossling, then adopt Emberfox.
        let ember = roster.adopt("emberfox", replacing: moss, lifetimeMeters: 17_000, on: day, at: now)
        XCTAssertEqual(ember.growth(lifetimeMeters: 17_000).kilometres, 0, "a new companion starts as a hatchling")
        XCTAssertEqual(roster.resting.first?.growth.kilometres, 7)
        // Walk 4 km with Emberfox, then swap back: Mossling picks up at 7 km.
        let back = roster.swap(active: ember, to: "mossling", lifetimeMeters: 21_000, at: now.addingTimeInterval(60))
        XCTAssertEqual(back?.growth(lifetimeMeters: 21_000).kilometres, 7, "resting companions don't grow")
        XCTAssertEqual(back?.growth(lifetimeMeters: 26_000).kilometres, 12, "and grow again when walking")
        XCTAssertEqual(roster.resting.first?.state.speciesID, "emberfox")
        XCTAssertEqual(roster.resting.first?.growth.kilometres, 4)
        XCTAssertNil(roster.swap(active: back!, to: "moonmoth", lifetimeMeters: 21_000, at: now), "can't wake one you don't own")
        XCTAssertEqual(roster.adoptable(active: back).map(\.id), ["moonmoth"])
    }

    func testAdoptionIsPaidOncePerSpecies() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 900))
        XCTAssertTrue(wallet.spend(key: CompanionRoster.adoptionChargeKey("emberfox"), amount: CompanionRoster.adoptionCost))
        XCTAssertFalse(wallet.spend(key: CompanionRoster.adoptionChargeKey("emberfox"), amount: CompanionRoster.adoptionCost))
        XCTAssertEqual(wallet.coins, 500)
        XCTAssertFalse(WalletState(rules: CoinRules(starterCoins: 399))
            .with { $0.spend(key: "companion-moonmoth", amount: CompanionRoster.adoptionCost) }, "needs 400 coins")
    }

    func testTheLatestChoiceWinsAcrossPhonesAndNoCompanionIsLost() {
        var rosterA = CompanionRoster()
        let moss = CompanionState(speciesID: "mossling", adoptedOn: day, lifetimeMeters: 0)
        let emberA = rosterA.adopt("emberfox", replacing: moss, lifetimeMeters: 5_000, on: day, at: now)
        // Phone B still has the old save: only Mossling.
        let merged = CompanionRoster.merge((emberA, rosterA), (moss, CompanionRoster()), lifetimeMeters: 8_000)
        XCTAssertEqual(merged.active?.speciesID, "emberfox")
        XCTAssertEqual(merged.active?.growth(lifetimeMeters: 8_000).kilometres, 3)
        XCTAssertEqual(merged.roster.resting.map(\.state.speciesID), ["mossling"])
        XCTAssertEqual(merged.roster.resting.first?.growth.kilometres, 5)
        let again = CompanionRoster.merge((merged.active, merged.roster), (moss, CompanionRoster()), lifetimeMeters: 8_000)
        XCTAssertEqual(again.active?.speciesID, merged.active?.speciesID, "merging again changes nothing")
        XCTAssertEqual(again.roster, merged.roster)
    }

    func testANewPhonesFirstPickIsNotAFreeCompanion() {
        let old = CompanionState(speciesID: "emberfox", adoptedOn: day, lifetimeMeters: 0)
        let firstPick = CompanionState(speciesID: "mossling", adoptedOn: day.adding(days: 3), lifetimeMeters: 0)
        let merged = CompanionRoster.merge((firstPick, CompanionRoster()), (old, CompanionRoster()), lifetimeMeters: 9_000)
        XCTAssertEqual(merged.active?.speciesID, "emberfox", "the companion adopted first is kept")
        XCTAssertTrue(merged.roster.resting.isEmpty)
    }

    func testOlderCompanionSavesStillLoad() throws {
        let json = #"{"speciesID":"moonmoth","adoptedOn":"2026-10-20","baselineMeters":1200,"celebratedStage":1}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertNil(state.activeSince)
        XCTAssertEqual(state.walkedMeters(lifetimeMeters: 3_200), 2_000)
    }
}

private extension WalletState {
    func with(_ change: (inout WalletState) -> Bool) -> Bool {
        var copy = self
        return change(&copy)
    }
}
