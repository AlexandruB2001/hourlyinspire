import XCTest
@testable import WalkscapeDomain

final class JourneyFeatureTests: XCTestCase {
    let today = LocalDay(year: 2026, month: 10, day: 28)
    let engine = ZoneProgressionEngine()

    func progress(_ meters: Int, day: LocalDay? = nil) -> DailyProgress {
        DailyProgress(userID: "me", localDate: day ?? today, timeZoneIdentifier: "UTC",
                      steps: meters, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date())
    }

    // MARK: Day browser

    func testDayBrowserNeverGoesPastToday() {
        var browser = DayBrowser(today: today, earliest: today.adding(days: -2))
        XCTAssertTrue(browser.isToday)
        XCTAssertFalse(browser.canGoForward)
        browser.goForward()
        XCTAssertEqual(browser.selected, today)
        browser.goBack()
        browser.goBack()
        XCTAssertEqual(browser.selected, today.adding(days: -2))
        XCTAssertFalse(browser.canGoBack)
        browser.goBack()
        XCTAssertEqual(browser.selected, today.adding(days: -2))
        browser.goForward()
        XCTAssertTrue(browser.canGoForward)
        browser.jumpToToday()
        XCTAssertTrue(browser.isToday)
        // A future selection is clamped.
        XCTAssertEqual(DayBrowser(today: today, earliest: today, selected: today.adding(days: 5)).selected, today)
    }

    func testEarliestDayUsesRecordedHistoryOrLookback() {
        XCTAssertEqual(DayBrowser.earliestDay(today: today, recordedDays: ["2026-01-02", "bad"], lookback: 30),
                       LocalDay(year: 2026, month: 1, day: 2))
        XCTAssertEqual(DayBrowser.earliestDay(today: today, recordedDays: [String](), lookback: 30), today.adding(days: -30))
    }

    // MARK: Companions

    func testCompanionGrowthIsSlowAndStaged() {
        XCTAssertEqual(CompanionGrowth(kilometres: 0).stage, .hatchling)
        XCTAssertEqual(CompanionGrowth(kilometres: 4).stage, .hatchling)
        XCTAssertEqual(CompanionGrowth(kilometres: 5).stage, .sprout)
        XCTAssertEqual(CompanionGrowth(kilometres: 20).stage, .companion)
        XCTAssertEqual(CompanionGrowth(kilometres: 50).stage, .guardian)
        XCTAssertEqual(CompanionGrowth(kilometres: 100).stage, .elder)
        XCTAssertEqual(CompanionGrowth(kilometres: 12).kilometresIntoStage, 7)
        XCTAssertEqual(CompanionGrowth(kilometres: 12).kilometresToNextStage, 8)
        XCTAssertNil(CompanionGrowth(kilometres: 400).kilometresToNextStage)
        XCTAssertEqual(CompanionGrowth(kilometres: 400).fractionToNextStage, 1)
    }

    func testCompanionsGrowFromAdoptionNotFromOldWalking() {
        var companion = CompanionState(speciesID: "mossling", adoptedOn: today, lifetimeMeters: 80_000)
        XCTAssertEqual(companion.growth(lifetimeMeters: 80_000).stage, .hatchling, "a veteran's new companion starts small")
        XCTAssertEqual(companion.growth(lifetimeMeters: 80_999).kilometres, 0)
        XCTAssertEqual(companion.newEvolutions(lifetimeMeters: 84_000), [])
        XCTAssertEqual(companion.newEvolutions(lifetimeMeters: 101_000), [.sprout, .companion])
        XCTAssertEqual(companion.newEvolutions(lifetimeMeters: 101_000), [], "each evolution is reported once")
        XCTAssertEqual(CompanionCatalog.starters.map(\.id), ["mossling", "emberfox", "moonmoth"])
    }

    // MARK: Journal

    func testJournalRecordsEachEventOnce() {
        var state = ProgressionState()
        _ = state.apply(progress(10_400), using: engine)
        var journal = JourneyJournal()
        let first = journal.record(JournalEvents.entries(progression: state, today: today))
        XCTAssertTrue(first.contains { $0.id == "zone-riverside" })
        XCTAssertTrue(first.contains { $0.id == "relic-summit-flag" })
        XCTAssertTrue(first.contains { $0.id == "day-5000-2026-10-28" })
        XCTAssertTrue(first.contains { $0.id == "day-10000-2026-10-28" })
        XCTAssertTrue(first.contains { $0.id == "lifetime-10000" })
        XCTAssertTrue(first.contains { $0.id == "achievement-first-steps" })
        XCTAssertFalse(first.contains { $0.id == "zone-meadow" }, "the starting zone isn't a milestone")
        XCTAssertEqual(journal.record(JournalEvents.entries(progression: state, today: today.adding(days: 1))), [],
                       "recalculating the same state adds nothing")
        XCTAssertEqual(journal.entries.count, first.count)
    }

    func testJournalTimelineIsNewestFirstAndRoundTrips() throws {
        var journal = JourneyJournal()
        let companion = CompanionState(speciesID: "emberfox", adoptedOn: today.adding(days: -3), lifetimeMeters: 0)
        journal.record([JournalEvents.adoption(of: companion)])
        journal.record([JournalEvents.evolution(.sprout, of: companion, on: today)])
        journal.record([JournalEvents.referralChest(id: "abc", coins: 40, on: today.adding(days: -1))])
        XCTAssertEqual(journal.timeline.map(\.kind), [.companion, .referral, .companion])
        XCTAssertEqual(journal.timeline.first?.title, "Emberfox became a Sprout")
        let decoded = try JSONDecoder().decode(JourneyJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertEqual(decoded, journal)
    }

    // MARK: Referral chests in the wallet

    func testReferralChestsPayOnce() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        let chest = ReferralChest(id: "r1", coins: 63)
        XCTAssertEqual(wallet.receiveReferralChests([chest, chest]), [chest])
        XCTAssertEqual(wallet.receiveReferralChests([chest]), [], "a waiting chest isn't added twice")
        XCTAssertEqual(wallet.openReferralChest(id: "r1"), 63)
        XCTAssertNil(wallet.openReferralChest(id: "r1"))
        XCTAssertEqual(wallet.receiveReferralChests([chest]), [], "an opened chest is never offered again")
        XCTAssertEqual(wallet.coins, 63)
    }

    func testWalletsSavedBeforeReferralsStillLoad() throws {
        let saved = """
        {"coins":180,"lifetimeCoins":420,"ownedItemIDs":["straw-hat"],"equipped":{"head":"straw-hat"},
         "pendingChests":2,"day":"2026-10-27","kilometresRewardedToday":3,"chestsFoundToday":6}
        """
        let wallet = try JSONDecoder().decode(WalletState.self, from: Data(saved.utf8))
        XCTAssertEqual(wallet.coins, 180)
        XCTAssertEqual(wallet.outfit, ["straw-hat"])
        XCTAssertEqual(wallet.pendingChests, 2)
        XCTAssertTrue(wallet.referralChests.isEmpty)
    }

    func testReferralCodesNormalize() {
        XCTAssertEqual(ReferralRules.normalize(" ab12-cd 34 "), "AB12CD34")
        XCTAssertTrue(ReferralRules.summary.contains("25–100 coins"))
    }

    // MARK: Teams

    func testTeamWeeksStartOnMonday() {
        XCTAssertEqual(TeamWeek.start(of: LocalDay(year: 2026, month: 10, day: 28)), LocalDay(year: 2026, month: 10, day: 26))
        XCTAssertEqual(TeamWeek.start(of: LocalDay(year: 2026, month: 10, day: 26)), LocalDay(year: 2026, month: 10, day: 26))
        XCTAssertEqual(TeamWeek.start(of: LocalDay(year: 2026, month: 11, day: 1)), LocalDay(year: 2026, month: 10, day: 26))
    }

    func testExpeditionsRunOneAfterAnother() {
        let start = ExpeditionProgress(totalMeters: 0)
        XCTAssertEqual(start.current?.id, "meadow-ramble")
        XCTAssertEqual(start.fraction, 0)
        let middle = ExpeditionProgress(totalMeters: 25_000 + 37_500)
        XCTAssertEqual(middle.completed.map(\.id), ["meadow-ramble"])
        XCTAssertEqual(middle.current?.id, "summit-relay")
        XCTAssertEqual(middle.fraction, 0.5, accuracy: 0.0001)
        let done = ExpeditionProgress(totalMeters: 10_000_000)
        XCTAssertNil(done.current)
        XCTAssertEqual(done.completed.count, ExpeditionCatalog.all.count)
        XCTAssertEqual(done.fraction, 1)
    }

    func testTeamDashboardTotalsOnlyCountSharingMembers() {
        let team = Team(id: "t", name: "Trail Blazers", joinCode: "ABC123", memberCount: 3, isOwner: true,
                        createdOn: today, totalMeters: 30_000)
        let members = [
            TeamMember(id: "a", username: "ana", avatarID: "fern", isCurrentUser: true, isOwner: true,
                       daySteps: 4_000, dayMeters: 3_000, weekMeters: 20_000, updatedAt: nil),
            TeamMember(id: "b", username: "ben", avatarID: "sky", isCurrentUser: false, isOwner: false,
                       daySteps: 8_000, dayMeters: 6_000, weekMeters: 9_000, updatedAt: nil),
            TeamMember(id: "c", username: "cat", avatarID: "plum", isCurrentUser: false, isOwner: false,
                       daySteps: nil, dayMeters: nil, weekMeters: nil, updatedAt: nil),
        ]
        let dashboard = TeamDashboard(team: team, members: members,
                                      standings: [TeamStanding(id: "t", name: "Trail Blazers", memberCount: 3,
                                                               weekMeters: 29_000, rank: 2, isMine: true)],
                                      weekStart: TeamWeek.start(of: today))
        XCTAssertEqual(dashboard.dayMeters, 9_000)
        XCTAssertEqual(dashboard.weekMeters, 29_000)
        XCTAssertEqual(dashboard.membersByToday.map(\.username), ["ben", "ana", "cat"])
        XCTAssertFalse(members[2].isSharing)
        XCTAssertEqual(dashboard.myStanding?.rank, 2)
        XCTAssertEqual(dashboard.badges.map(\.id), ["week-25000", "expedition-meadow-ramble"])
    }
}
