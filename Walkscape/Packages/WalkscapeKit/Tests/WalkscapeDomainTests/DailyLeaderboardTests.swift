import XCTest
@testable import WalkscapeDomain

final class DailyLeaderboardTests: XCTestCase {
    func row(_ name: String, rank: Int?, meters: Int, me: Bool = false) -> DailyLeaderboardRow {
        DailyLeaderboardRow(userID: UserID(name), username: name, avatarID: "fern", outfit: [], rank: rank, meters: meters, isMe: me)
    }

    func testShowsTheTopThreeAndYourLine() {
        let board = DailyLeaderboard(rows: [row("a", rank: 1, meters: 9_000), row("b", rank: 2, meters: 8_000),
                                            row("c", rank: 3, meters: 7_000), row("me", rank: 14, meters: 3_000, me: true)],
                                     players: 62, isUnderReview: false, isShownToOthers: true)
        XCTAssertEqual(board.top.map(\.username), ["a", "b", "c"])
        XCTAssertEqual(board.me?.username, "me")
        XCTAssertEqual(board.myStatus, .ranked(rank: 14, of: 62))
    }

    func testBeingInTheTopThreeStillGivesYourLine() {
        let board = DailyLeaderboard(rows: [row("me", rank: 1, meters: 9_000, me: true), row("b", rank: 2, meters: 8_000)],
                                     players: 2, isUnderReview: false, isShownToOthers: true)
        XCTAssertEqual(board.top.count, 2)
        XCTAssertEqual(board.myStatus, .ranked(rank: 1, of: 2))
    }

    func testUnrankedDaysSayWhy() {
        func status(meters: Int, review: Bool) -> DailyLeaderboardStatus {
            DailyLeaderboard(rows: [row("me", rank: nil, meters: meters, me: true)], players: 5, isUnderReview: review, isShownToOthers: true).myStatus
        }
        XCTAssertEqual(status(meters: 0, review: false), .notWalked)
        XCTAssertEqual(status(meters: 2_000, review: false), .estimated)
        XCTAssertEqual(status(meters: 40_000, review: true), .underReview)
        XCTAssertTrue(DailyLeaderboard(rows: [row("me", rank: nil, meters: 0, me: true)], players: 5, isUnderReview: false,
                                       isShownToOthers: true).top.isEmpty, "unranked walkers aren't in the top")
    }
}
