import XCTest
@testable import WalkscapeDomain

final class QuestTests: XCTestCase {
    let engine = ZoneProgressionEngine()
    // Thursday 29 October 2026; its week starts Monday 26 October.
    let thursday = LocalDay(year: 2026, month: 10, day: 29)
    let monday = LocalDay(year: 2026, month: 10, day: 26)

    func progress(_ meters: Int, on day: LocalDay) -> DailyProgress {
        DailyProgress(userID: "me", localDate: day, timeZoneIdentifier: "Europe/London",
                      steps: meters * 13 / 10, distanceMeters: meters, distanceSource: .recorded, updatedAt: Date())
    }

    let everything = QuestContext(hasFriends: true, inTeam: true, hasCompanion: true, zonesLeftToDiscover: 20,
                                  metersLeftInExpedition: 10_000, companionKilometresToNextStage: 3)

    // MARK: Catalog sanity

    func testQuestsStayAchievable() {
        for quest in QuestCatalog.daily {
            switch quest.goal {
            case .metersToday(let m): XCTAssertLessThanOrEqual(m, 3_000, quest.id)
            case .stepsToday(let s): XCTAssertLessThanOrEqual(s, 5_000, quest.id)
            default: break
            }
        }
        for quest in QuestCatalog.weekly + QuestCatalog.companion {
            if case .metersThisWeek(let m) = quest.goal { XCTAssertLessThanOrEqual(m, 15_000, quest.id) }
        }
        let ids = (QuestCatalog.daily + QuestCatalog.weekly + QuestCatalog.companion).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "quest ids are unique")
    }

    // MARK: Planner

    func testBoardsAreDeterministicAndVaried() {
        let a = QuestPlanner.daily(for: thursday, context: everything)
        XCTAssertEqual(a, QuestPlanner.daily(for: thursday, context: everything))
        XCTAssertEqual(a.count, 3)
        XCTAssertEqual(Set(a).count, 3)
        let goals = a.compactMap { QuestCatalog.definition(withID: $0)?.goal }
        for (i, g) in goals.enumerated() {
            for h in goals[(i + 1)...] { XCTAssertFalse(QuestPlanner.sameFamily(g, h), "no near-duplicate quests") }
        }
        let week = (0..<14).map { QuestPlanner.daily(for: thursday.adding(days: $0), context: everything) }
        XCTAssertGreaterThan(Set(week.flatMap { $0 }).count, 4, "different days get different quests")
    }

    func testQuestsNeedingFriendsOrTeamsAreOnlyOfferedWhenPossible() {
        let alone = QuestContext(zonesLeftToDiscover: 0)
        for offset in 0..<30 {
            let day = thursday.adding(days: offset)
            XCTAssertFalse(QuestPlanner.daily(for: day, context: alone).contains("friend-walk"))
            XCTAssertFalse(QuestPlanner.daily(for: day, context: alone).contains("new-zone"))
            let weekly = QuestPlanner.weekly(for: TeamWeek.start(of: day), context: alone)
            XCTAssertFalse(weekly.contains("week-team") || weekly.contains("week-expedition") || weekly.contains("week-zones"))
            XCTAssertTrue(QuestPlanner.companion(for: day, context: alone).isEmpty)
        }
    }

    // MARK: Tracker and resets

    func testDailyBoardResetsAtMidnightAndWeeklyOnMonday() {
        var tracker = QuestTracker()
        let wallet = WalletState()
        tracker.roll(to: thursday, context: everything, wallet: wallet, companionStage: 0)
        let weekly = tracker.weeklyQuestIDs
        tracker.recordChestOpened()
        tracker.recordChestsFound(2, on: thursday)

        tracker.roll(to: thursday, context: QuestContext(), wallet: wallet, companionStage: 0)
        XCTAssertEqual(tracker.chestsOpenedToday, 1, "rolling to the same day changes nothing")

        let friday = thursday.adding(days: 1)
        tracker.roll(to: friday, context: everything, wallet: wallet, companionStage: 0)
        XCTAssertEqual(tracker.chestsOpenedToday, 0)
        XCTAssertEqual(tracker.weeklyQuestIDs, weekly, "same week, same weekly quests")
        XCTAssertEqual(tracker.chestsFoundThisWeek, 2)

        let nextMonday = monday.adding(days: 7)
        tracker.roll(to: nextMonday, context: everything, wallet: wallet, companionStage: 0)
        XCTAssertEqual(tracker.week, nextMonday)
        XCTAssertEqual(tracker.chestsFoundThisWeek, 0)
    }

    func testTheBoardDoesNotChangeMidDayWhenContextChanges() {
        var tracker = QuestTracker()
        tracker.roll(to: thursday, context: QuestContext(), wallet: WalletState(), companionStage: nil)
        let before = tracker.dailyQuestIDs
        tracker.roll(to: thursday, context: everything, wallet: WalletState(), companionStage: 0)
        XCTAssertEqual(tracker.dailyQuestIDs, before)
    }

    // MARK: Progress and claiming

    func board(meters: [LocalDay: Int], today: LocalDay, tracker: inout QuestTracker, ledger: RewardLedger,
               wallet: WalletState = WalletState(), journal: JourneyJournal = JourneyJournal(),
               friend: Bool = false) -> (QuestBoard, QuestFacts) {
        var state = ProgressionState()
        for day in meters.keys.sorted() { _ = state.apply(progress(meters[day]!, on: day), using: engine) }
        tracker.roll(to: today, context: everything, wallet: wallet, companionStage: 0)
        let todayMeters = meters[today] ?? 0
        let facts = QuestFacts.make(today: today, steps: todayMeters * 13 / 10, meters: todayMeters, progression: state,
                                    wallet: wallet, journal: journal, tracker: tracker, friendWalkedToday: friend,
                                    teamMetersThisWeek: 0, companionStage: 0)
        return (QuestBoard(tracker: tracker, facts: facts, ledger: ledger), facts)
    }

    func testWeeklyProgressComesFromBestDistancePerDay() {
        var tracker = QuestTracker()
        let (_, facts) = board(meters: [monday: 3_000, monday.adding(days: 1): 1_200, thursday: 2_500,
                                        monday.adding(days: -1): 9_000],   // last Sunday doesn't count
                               today: thursday, tracker: &tracker, ledger: RewardLedger())
        XCTAssertEqual(facts.metersThisWeek, 6_700)
        XCTAssertEqual(facts.activeDaysThisWeek(minimumMeters: 1_000), 3)
        XCTAssertEqual(facts.progress(of: .metersThisWeek(15_000)), 6_700)
        XCTAssertEqual(facts.progress(of: .metersThisWeek(5_000)), 5_000, "progress is capped at the target")
    }

    func testCoinsEarnedTodayAndFriendWalks() {
        var tracker = QuestTracker()
        var wallet = WalletState(rules: CoinRules(starterCoins: 100))
        tracker.roll(to: thursday, context: everything, wallet: wallet, companionStage: 0)
        _ = wallet.apply(progress(3_200, on: thursday))   // 30 coins for 3 km
        let (_, facts) = board(meters: [thursday: 3_200], today: thursday, tracker: &tracker, ledger: RewardLedger(),
                               wallet: wallet, friend: true)
        XCTAssertEqual(facts.coinsEarnedToday, 30)
        XCTAssertTrue(facts.friendWalkedToday)
        let (_, idle) = board(meters: [:], today: thursday, tracker: &tracker, ledger: RewardLedger(), friend: true)
        XCTAssertFalse(idle.friendWalkedToday, "you have to walk too")
    }

    func testCompletedQuestsPayOnceAndTheWeeklyChestNeedsEveryWeeklyQuest() {
        var tracker = QuestTracker()
        var ledger = RewardLedger()
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        let busyWeek: [LocalDay: Int] = Dictionary(uniqueKeysWithValues: (0..<7).map { (monday.adding(days: $0), 3_500) })
        var (board, _) = self.board(meters: busyWeek, today: monday.adding(days: 6), tracker: &tracker, ledger: ledger)
        let claimable = board.weekly.filter(\.isClaimable)
        XCTAssertFalse(claimable.isEmpty)
        XCTAssertFalse(board.weeklyChestReady)

        for status in board.weekly where status.isClaimable {
            XCTAssertTrue(ledger.claim(status.reward, into: &wallet))
            XCTAssertFalse(ledger.claim(status.reward, into: &wallet), "a quest pays once")
        }
        (board, _) = self.board(meters: busyWeek, today: monday.adding(days: 6), tracker: &tracker, ledger: ledger)
        if board.weekly.allSatisfy(\.isClaimed) {
            XCTAssertTrue(board.weeklyChestReady)
            XCTAssertTrue(ledger.claim(board.weeklyChest, into: &wallet))
            (board, _) = self.board(meters: busyWeek, today: monday.adding(days: 6), tracker: &tracker, ledger: ledger)
            XCTAssertFalse(board.weeklyChestReady, "the chest is claimed once")
        }
    }

    func testRewardIDsIncludeThePeriodSoEachDayPaysSeparately() {
        var tracker = QuestTracker()
        let (a, _) = board(meters: [thursday: 4_000], today: thursday, tracker: &tracker, ledger: RewardLedger())
        let (b, _) = board(meters: [thursday.adding(days: 1): 4_000], today: thursday.adding(days: 1), tracker: &tracker,
                           ledger: RewardLedger())
        XCTAssertTrue(a.daily.allSatisfy { $0.rewardID.contains(thursday.isoString) })
        XCTAssertTrue(Set(a.daily.map(\.rewardID)).isDisjoint(with: b.daily.map(\.rewardID)))
        XCTAssertTrue(a.weekly.allSatisfy { $0.rewardID.contains(monday.isoString) })
    }

    func testTrackerDecodesFromAnEmptySave() throws {
        let tracker = QuestTracker()
        let decoded = try JSONDecoder().decode(QuestTracker.self, from: JSONEncoder().encode(tracker))
        XCTAssertEqual(decoded, tracker)
    }
}
