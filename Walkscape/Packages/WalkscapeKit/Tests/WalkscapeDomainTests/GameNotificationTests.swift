import XCTest
@testable import WalkscapeDomain

final class GameNotificationTests: XCTestCase {
    let today = LocalDay(year: 2026, month: 10, day: 29)

    func entry(_ id: String, kind: JournalEntry.Kind = .zone, title: String = "Reached Meadow") -> JournalEntry {
        JournalEntry(id: id, kind: kind, day: today, title: title, detail: "detail", iconID: "icon")
    }

    func testChestNotificationsSayHowMuchTheyHold() throws {
        XCTAssertNil(GameNotifications.chests(0, on: today, total: 0))
        let one = try XCTUnwrap(GameNotifications.chests(1, on: today, total: 3))
        XCTAssertEqual(one.title, "You found a chest!")
        XCTAssertTrue(one.body.contains("5 coins"))
        XCTAssertEqual(one.destination, .journey)
        XCTAssertEqual(GameNotifications.chests(2, on: today, total: 5)?.title, "You found 2 chests!")
        // The same chest count on the same day is the same event.
        XCTAssertEqual(GameNotifications.chests(1, on: today, total: 3)?.id, one.id)
    }

    func testJournalEntriesBecomeRewardNotifications() {
        let zone = GameNotifications.journal(entry("zone-meadow"))
        XCTAssertEqual(zone.title, "New zone: Meadow")
        XCTAssertEqual(zone.category, .rewards)
        let achievement = GameNotifications.journal(entry("a", kind: .achievement, title: "Lightkeeper"))
        XCTAssertEqual(achievement.title, "Achievement unlocked: Lightkeeper")
        XCTAssertEqual(achievement.destination, .profile)
        XCTAssertEqual(GameNotifications.journal(entry("t", kind: .team, title: "Team")).destination, .friends)
    }

    func testManyMilestonesAtOnceAreFoldedIntoOne() {
        let few = (1...3).map { entry("e\($0)") }
        XCTAssertEqual(GameNotifications.journal(few, on: today).count, 3)
        let many = (1...6).map { entry("e\($0)") }
        let folded = GameNotifications.journal(many, on: today)
        XCTAssertEqual(folded.count, 1)
        XCTAssertEqual(folded[0].title, "6 new milestones!")
        XCTAssertEqual(GameNotifications.journal(many.reversed(), on: today)[0].id, folded[0].id)
    }

    func testSocialNotificationsNameTheFriend() {
        let invite = GameNotifications.teamInvite(TeamInvite(id: "i1", teamName: "Trail Blazers", fromUsername: "sam"))
        XCTAssertEqual(invite.category, .social)
        XCTAssertEqual(invite.body, "@sam invited you to join Trail Blazers.")
        let request = GameNotifications.friendRequest(FriendRequest(id: "r1", userID: "u", username: "kim", avatarID: "a",
                                                                    direction: .incoming, createdAt: Date()))
        XCTAssertEqual(request.body, "@kim wants to walk with you.")
        XCTAssertEqual(GameNotifications.dailyReminder(companionName: "Mossling").body,
                       "Mossling is ready for a walk. Every step counts!")
    }

    func testPreferencesFilterByCategory() {
        var preferences = NotificationPreferences()
        XCTAssertTrue(preferences.allows(.rewards))
        XCTAssertTrue(preferences.allows(.social))
        XCTAssertFalse(preferences.allows(.reminder))
        preferences.rewards = false
        XCTAssertFalse(preferences.allows(.rewards))
        XCTAssertEqual(NotificationPreferences(reminderHour: 30).reminderHour, 23)
    }

    func testLedgerNeverAnnouncesTheSameEventTwice() throws {
        var ledger = NotificationLedger()
        let invite = GameNotifications.teamInvite(TeamInvite(id: "i1", teamName: "T", fromUsername: "sam"))
        let chest = try XCTUnwrap(GameNotifications.chests(1, on: today, total: 1))
        XCTAssertEqual(ledger.unannounced([invite, chest]).count, 2)
        XCTAssertEqual(ledger.unannounced([invite, chest]), [])
        ledger.markSeen([GameNotifications.journal(entry("old"))])
        XCTAssertEqual(ledger.unannounced([GameNotifications.journal(entry("old"))]), [])

        let decoded = try JSONDecoder().decode(NotificationLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
    }

    func testLedgerForgetsTheOldestPastCapacity() {
        var ledger = NotificationLedger()
        let many = (0..<(NotificationLedger.capacity + 10)).map {
            GameNotification(id: "n\($0)", category: .rewards, title: "", body: "", destination: .journey)
        }
        _ = ledger.unannounced(many)
        XCTAssertEqual(ledger.announcedIDs.count, NotificationLedger.capacity)
        XCTAssertEqual(ledger.announcedIDs.first, "n10")
    }
}
