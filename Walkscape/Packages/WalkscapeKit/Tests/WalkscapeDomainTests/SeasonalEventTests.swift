import XCTest
@testable import WalkscapeDomain

final class SeasonalEventTests: XCTestCase {
    let engine = ZoneProgressionEngine()

    func walked(_ days: [(LocalDay, Int)]) -> ProgressionState {
        var state = ProgressionState()
        for (day, meters) in days.sorted(by: { $0.0 < $1.0 }) {
            _ = state.apply(DailyProgress(userID: "me", localDate: day, timeZoneIdentifier: "UTC", steps: meters,
                                          distanceMeters: meters, distanceSource: .recorded, updatedAt: Date()), using: engine)
        }
        return state
    }

    func testEventsRecurEveryYearIncludingOnesThatCrossNewYear() {
        let harvest = SeasonalEventCatalog.event(withID: "great-harvest")!
        let run2026 = SeasonalEventCatalog.run(of: harvest, around: LocalDay(year: 2026, month: 10, day: 30))
        XCTAssertEqual(run2026.startDay, LocalDay(year: 2026, month: 10, day: 15))
        XCTAssertEqual(run2026.id, "great-harvest-2026")
        XCTAssertTrue(run2026.contains(LocalDay(year: 2026, month: 11, day: 12)))
        XCTAssertFalse(run2026.contains(LocalDay(year: 2026, month: 11, day: 13)))
        let run2027 = SeasonalEventCatalog.run(of: harvest, around: LocalDay(year: 2026, month: 12, day: 1))
        XCTAssertEqual(run2027.id, "great-harvest-2027", "a missed event comes back next year")

        let winter = SeasonalEventCatalog.event(withID: "winter-wanderer")!
        let newYear = SeasonalEventCatalog.run(of: winter, around: LocalDay(year: 2027, month: 1, day: 5))
        XCTAssertEqual(newYear.startDay, LocalDay(year: 2026, month: 12, day: 15))
        XCTAssertEqual(newYear.endDay, LocalDay(year: 2027, month: 1, day: 12))
        XCTAssertTrue(newYear.contains(LocalDay(year: 2027, month: 1, day: 5)))
        XCTAssertEqual(newYear.daysLeft(from: LocalDay(year: 2027, month: 1, day: 10)), 3)
    }

    func testActiveAndNextEvents() {
        XCTAssertEqual(SeasonalEventCatalog.active(on: LocalDay(year: 2026, month: 10, day: 30)).map(\.event.id), ["great-harvest"])
        XCTAssertTrue(SeasonalEventCatalog.active(on: LocalDay(year: 2026, month: 5, day: 30)).isEmpty)
        XCTAssertEqual(SeasonalEventCatalog.next(after: LocalDay(year: 2026, month: 11, day: 20))?.event.id, "winter-wanderer")
        // Never two events at once.
        var day = LocalDay(year: 2026, month: 1, day: 1)
        for _ in 0..<366 {
            XCTAssertLessThanOrEqual(SeasonalEventCatalog.active(on: day).count, 1, day.isoString)
            day = day.adding(days: 1)
        }
    }

    func testProgressCountsOnlyEventDaysAndCapsBigOnes() {
        let harvest = SeasonalEventCatalog.event(withID: "great-harvest")!
        let run = SeasonalEventCatalog.run(of: harvest, around: LocalDay(year: 2026, month: 10, day: 30))
        let state = walked([(LocalDay(year: 2026, month: 10, day: 14), 8_000),  // the day before: doesn't count
                            (LocalDay(year: 2026, month: 10, day: 15), 4_000),
                            (LocalDay(year: 2026, month: 10, day: 20), 30_000),  // capped at 10 km
                            (LocalDay(year: 2026, month: 10, day: 21), 2_500)])
        let progress = EventProgress(run: run, progression: state, collections: CollectionState())
        XCTAssertEqual(progress.kilometres, 16)
        XCTAssertEqual(progress.activeDays, 3)
        XCTAssertEqual(progress.tiersReached, 2)
        XCTAssertEqual(progress.nextTier?.kilometres, 30)
        let ids = progress.unlockedRewards.map(\.id)
        XCTAssertEqual(ids, ["event-great-harvest-2026-tier-1", "event-great-harvest-2026-tier-2"])
        XCTAssertEqual(progress.unlockedRewards[1].itemIDs, ["pet-pumpkin-hat"])
    }

    func testEventCosmeticsAreEarnedDuringTheEventAndSoldAfter() {
        let hat = CompanionAccessoryCatalog.accessory(withID: "pet-pumpkin-hat")!
        XCTAssertFalse(hat.isInMysteryBox(on: LocalDay(year: 2026, month: 10, day: 30)))
        XCTAssertTrue(hat.isInMysteryBox(on: LocalDay(year: 2026, month: 12, day: 1)))
        for event in SeasonalEventCatalog.all {
            for item in event.tiers.flatMap(\.itemIDs) {
                XCTAssertEqual(CompanionAccessoryCatalog.accessory(withID: item)?.eventID, event.id, item)
            }
            XCTAssertNotNil(TitleCatalog.title(withID: event.titleID), event.id)
            let km = event.tiers.map(\.kilometres)
            XCTAssertEqual(km, km.sorted())
            XCTAssertLessThanOrEqual(km.last ?? 0, 50, "events never ask for more than 50 km over several weeks")
        }
    }

    func testFinishingAnEventUnlocksItsTitle() {
        var ledger = RewardLedger()
        var wallet = WalletState()
        let facts = { ProfileFacts(progression: ProgressionState(), explorerLevel: 1, ledger: ledger, journal: JourneyJournal(),
                                   companionStage: nil) }
        let title = TitleCatalog.title(withID: "harvest-keeper")!
        XCTAssertFalse(title.requirement.isMet(by: facts()))
        ledger.claim(Reward(id: "event-great-harvest-2026-tier-4"), into: &wallet)
        XCTAssertTrue(title.requirement.isMet(by: facts()))
    }
}
