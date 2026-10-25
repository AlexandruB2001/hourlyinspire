import XCTest
@testable import WalkscapeDomain

final class MockFriendRepositoryTests: XCTestCase {
    let today = LocalDay(year: 2026, month: 10, day: 25)

    func testSummariesReflectAvailability() async throws {
        let repo = MockFriendRepository()
        let summaries = try await repo.friendSummaries(for: today, now: Date())
        let byName = Dictionary(uniqueKeysWithValues: summaries.map { ($0.username, $0) })
        XCTAssertEqual(byName["Taylor"]?.dailyDistanceMeters, 7_200)
        XCTAssertEqual(byName["Taylor"]?.currentZoneID, "snowy-ridge")
        XCTAssertEqual(byName["Sam"]?.progressAvailability, .stale)
        XCTAssertEqual(byName["Riley"]?.progressAvailability, .unavailable)
        XCTAssertNil(byName["Riley"]?.dailyDistanceMeters)
    }

    func testRequestRules() async throws {
        let repo = MockFriendRepository()
        await XCTAssertThrowsAsync(try await repo.sendFriendRequest(toUsername: "Alex"), .alreadyFriends)
        await XCTAssertThrowsAsync(try await repo.sendFriendRequest(toUsername: "jordan"), .requestAlreadyPending)
        await XCTAssertThrowsAsync(try await repo.sendFriendRequest(toUsername: "  "), .userNotFound)
        try await repo.sendFriendRequest(toUsername: "Morgan")
        let outgoing = try await repo.friendRequests().outgoing.map(\.username)
        XCTAssertEqual(outgoing, ["Jordan", "Morgan"])

        try await repo.acceptFriendRequest(id: "req-casey")
        let names = try await repo.friendSummaries(for: today, now: Date()).map(\.username)
        XCTAssertTrue(names.contains("Casey"))

        try await repo.blockUser("u-alex")
        let afterBlock = try await repo.friendSummaries(for: today, now: Date()).map(\.username)
        XCTAssertFalse(afterBlock.contains("Alex"))
    }
}

func XCTAssertThrowsAsync(_ expression: @autoclosure () async throws -> Void, _ expected: FriendRepositoryError,
                          file: StaticString = #filePath, line: UInt = #line) async {
    do {
        try await expression()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? FriendRepositoryError, expected, file: file, line: line)
    }
}
