import XCTest
@testable import WalkscapeDomain

final class TeamMapTests: XCTestCase {
    func testAStopEveryFiveKilometres() {
        XCTAssertGreaterThan(TeamMap.waypointCount, 20, "the map is a long trail")
        XCTAssertEqual(TeamMap.reachedWaypoint(teamMeters: 0), 0)
        XCTAssertEqual(TeamMap.reachedWaypoint(teamMeters: 4_999), 0)
        XCTAssertEqual(TeamMap.reachedWaypoint(teamMeters: 5_000), 1)
        XCTAssertEqual(TeamMap.reachedWaypoint(teamMeters: 23_400), 4)
        XCTAssertEqual(TeamMap.reachedWaypoint(teamMeters: -10), 0)
        XCTAssertEqual(TeamMap.reachedWaypoint(teamMeters: 100_000_000), TeamMap.waypointCount, "the last stop is the end")
    }

    func testLandmarksAreInOrderOnTheRouteAndEachBelongsToOneStop() {
        let marks = TeamMap.landmarks
        XCTAssertFalse(marks.isEmpty)
        XCTAssertEqual(marks.map(\.meters), marks.map(\.meters).sorted())
        XCTAssertEqual(Set(marks.map(\.id)).count, marks.count)
        XCTAssertTrue(marks.allSatisfy { $0.meters > 0 && $0.meters <= TeamMap.lengthMeters })
        let placed = (0...TeamMap.waypointCount).flatMap { TeamMap.landmarks(atWaypoint: $0) }
        XCTAssertEqual(placed.count, marks.count)
        XCTAssertTrue(Set(marks.map(\.kind)).isSuperset(of: [.campfire, .expedition, .worldZone]))
    }

    func testRegionsFollowTheTeamWorlds() {
        XCTAssertNil(TeamMap.world(atWaypoint: 0), "the route starts on the home trail")
        let first = TeamWorldCatalog.worlds[0]
        let opens = TeamWorldCatalog.startMeters(of: first) / TeamMap.waypointMeters
        XCTAssertEqual(TeamMap.world(atWaypoint: opens + 1)?.id, first.id)
        XCTAssertEqual(TeamMap.world(atWaypoint: TeamMap.waypointCount)?.id, TeamWorldCatalog.worlds.last?.id)
    }

    func testChallengesAreSharedByTheWholeTeamAndPaidOncePerStop() {
        let a = WaypointChallenge(waypoint: 3, teamID: "team-1", memberCount: 4)
        XCTAssertEqual(a, WaypointChallenge(waypoint: 3, teamID: "team-1", memberCount: 4), "every member sees the same one")
        let rewards = (1...40).map { WaypointChallenge(waypoint: $0, teamID: "team-1", memberCount: 4).reward.id }
        XCTAssertEqual(Set(rewards).count, 40)
        let kinds = Set((1...60).map { "\(WaypointChallenge(waypoint: $0, teamID: "team-1", memberCount: 4).kind)".prefix(5) })
        XCTAssertGreaterThan(kinds.count, 1, "stops mix up the challenge types")
        if case .push = WaypointChallenge(waypoint: 9, teamID: "solo", memberCount: 1).kind {} else {
            XCTFail("a one-person team always gets a distance push")
        }
    }

    func testChallengeProgress() {
        let push = WaypointChallenge(kind: .push(meters: 10_000))
        XCTAssertEqual(push.progress(todayMeters: [4_000, nil, 3_000]).done, 7_000)
        XCTAssertFalse(push.isComplete(todayMeters: [4_000, nil, 3_000]))
        XCTAssertTrue(push.isComplete(todayMeters: [8_000, 3_000]))

        let together = WaypointChallenge(kind: .together(members: 2, meters: 2_000))
        XCTAssertEqual(together.progress(todayMeters: [2_500, 1_999, nil]).done, 1)
        XCTAssertTrue(together.isComplete(todayMeters: [2_500, 2_000, 0]))

        let everyone = WaypointChallenge(kind: .everyone(meters: 1_000))
        XCTAssertFalse(everyone.isComplete(todayMeters: [1_200, nil]), "someone not sharing hasn't walked it")
        XCTAssertTrue(everyone.isComplete(todayMeters: [1_200, 1_000]))
    }
}

private extension WaypointChallenge {
    init(kind: Kind) {
        self.init(waypoint: 1, kind: kind)
    }
}
