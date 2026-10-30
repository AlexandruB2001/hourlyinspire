import XCTest
@testable import WalkscapeDomain

final class GroupTests: XCTestCase {
    func testCostsAndChargeKeysMatchTheServer() {
        XCTAssertEqual(CreationCosts.group, 500)
        XCTAssertEqual(CreationCosts.team, 25)
        let request = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD")!
        // Postgres writes uuids in lower case; the keys must match exactly.
        XCTAssertEqual(CreationCosts.chargeKey(.group, requestID: request), "group-0a1b2c3d-0000-4000-8000-00000000abcd")
        XCTAssertEqual(CreationCosts.chargeKey(.team, requestID: request), "team-0a1b2c3d-0000-4000-8000-00000000abcd")
    }

    func testAServerChargeCountsOnceHoweverItArrives() {
        var phone = WalletState(rules: CoinRules(starterCoins: 600))
        let key = CreationCosts.chargeKey(.group, requestID: UUID())
        var cloud = phone
        cloud.recordServerCharge(key: key, amount: CreationCosts.group)   // the server's write
        phone.recordServerCharge(key: key, amount: CreationCosts.group)   // the app's own record
        phone.recordServerCharge(key: key, amount: CreationCosts.group)   // a repeated success
        XCTAssertEqual(phone.coins, 100)
        XCTAssertEqual(phone.merged(with: cloud).coins, 100, "the phone and cloud copies are the same charge")
        var untouched = WalletState(rules: CoinRules(starterCoins: 600))
        XCTAssertEqual(untouched.merged(with: cloud).coins, 100, "a phone that missed the response still pays once")
        untouched.recordServerCharge(key: CreationCosts.chargeKey(.team, requestID: UUID()), amount: CreationCosts.team)
        XCTAssertEqual(untouched.merged(with: cloud).coins, 75, "a different creation is a different charge")
    }

    func testCodesFromTypingAndQRCodes() {
        XCTAssertEqual(GroupRules.code(from: " ab3-k9z "), "AB3K9Z")
        XCTAssertEqual(GroupRules.code(from: "walkscape://group/AB3K9Z"), "AB3K9Z")
        XCTAssertEqual(GroupRules.code(from: GroupRules.qrPayload(code: "XY7Q2M")), "XY7Q2M")
        XCTAssertNil(GroupRules.code(from: "AB3K9"), "too short")
        XCTAssertNil(GroupRules.code(from: "AB3K9ZZ"), "too long")
        XCTAssertNil(GroupRules.code(from: "AB0K1Z"), "0 and 1 are never used")
        XCTAssertNil(GroupRules.code(from: "https://example.com/AB3K9Z"))
    }

    func testGroupNamesFollowTheServerRules() {
        XCTAssertEqual(GroupRules.cleanName("  Fit4Less   Windsor "), "Fit4Less Windsor")
        XCTAssertEqual(GroupRules.cleanName("Friends & Family Walking Challenge"), "Friends & Family Walking Challenge")
        XCTAssertEqual(GroupRules.cleanName("Melo LLP Walking Group"), "Melo LLP Walking Group")
        XCTAssertNil(GroupRules.cleanName("ab"), "too short")
        XCTAssertNil(GroupRules.cleanName(String(repeating: "a", count: 41)), "too long")
        XCTAssertNil(GroupRules.cleanName("-Dashes first"), "must start with a letter or number")
        XCTAssertNil(GroupRules.cleanName("Emoji 🚶 Club"))
        XCTAssertTrue(GroupRules.isValidDescription(String(repeating: "a", count: 160)))
        XCTAssertFalse(GroupRules.isValidDescription(String(repeating: "a", count: 161)))
        XCTAssertEqual(Set(GroupRules.emblems).count, GroupRules.emblems.count)
        XCTAssertTrue(GroupRules.emblems.allSatisfy { $0.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil })
    }

    func testWeeksStartOnMonday() {
        let wednesday = LocalDay(year: 2026, month: 11, day: 4)
        XCTAssertEqual(LeaderboardPeriod.week.firstDay(for: wednesday), LocalDay(year: 2026, month: 11, day: 2))
        XCTAssertEqual(LeaderboardPeriod.week.firstDay(for: LocalDay(year: 2026, month: 11, day: 2)),
                       LocalDay(year: 2026, month: 11, day: 2), "Monday starts its own week")
        XCTAssertEqual(LeaderboardPeriod.week.firstDay(for: LocalDay(year: 2026, month: 11, day: 8)),
                       LocalDay(year: 2026, month: 11, day: 2), "Sunday still belongs to it")
        // Across a daylight-saving change (1 November in North America) the week is still Monday to Sunday.
        XCTAssertEqual(LeaderboardPeriod.week.firstDay(for: LocalDay(year: 2026, month: 11, day: 1)),
                       LocalDay(year: 2026, month: 10, day: 26))
        XCTAssertEqual(LeaderboardPeriod.day.firstDay(for: wednesday), wednesday)
    }

    func standing(_ name: String, rank: Int, meters: Int?, me: Bool = false) -> GroupStanding {
        GroupStanding(userID: UserID(name), username: name, avatarID: "fern", rank: rank, steps: meters.map { $0 * 13 / 10 },
                      meters: meters, estimated: false, updatedAt: nil, isMe: me)
    }

    func testTheCallerIsPinnedWhenOutsideThePage() {
        let page = GroupLeaderboardPage(period: .day, rows: [
            standing("ana", rank: 1, meters: 9_000), standing("ben", rank: 2, meters: 8_000), standing("me", rank: 37, meters: 900, me: true),
        ], memberCount: 50, limit: 2)
        XCTAssertEqual(page.rows.map(\.username), ["ana", "ben"])
        XCTAssertEqual(page.me?.rank, 37)
        XCTAssertTrue(page.meIsElsewhere)

        let inside = GroupLeaderboardPage(period: .week, rows: [
            standing("ana", rank: 1, meters: 9_000), standing("me", rank: 2, meters: 8_000, me: true),
        ], memberCount: 2, limit: 10)
        XCTAssertEqual(inside.rows.count, 2)
        XCTAssertFalse(inside.meIsElsewhere)
        XCTAssertFalse(standing("hidden", rank: 3, meters: nil).isSharing)
    }

    func testErrorsReadNicely() {
        XCTAssertTrue(GroupError.limitReached.message.contains("5 groups"))
        XCTAssertTrue(GroupError.insufficientCoins.message.contains("coins"))
    }

    func testTheSocialDropdownHasFriendsTeamsAndGroups() {
        XCTAssertEqual(SocialSection.allCases, [.friends, .teams, .groups], "menu order")
        XCTAssertEqual(SocialSection.allCases.map(\.rawValue), ["Friends", "Teams", "Groups"], "labels")
        XCTAssertEqual(SocialSection(rawValue: "Groups"), .groups, "the remembered choice comes back")
        XCTAssertNil(SocialSection(rawValue: "Team"), "an unknown stored value falls back to the default")
        XCTAssertEqual(Set(SocialSection.allCases.map(\.spriteID)).count, 3, "each has its own icon")
    }
}
