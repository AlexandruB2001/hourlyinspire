import XCTest
@testable import WalkscapeDomain

final class FriendTrackLayoutTests: XCTestCase {
    let config = TrackLayoutConfiguration(viewportWidth: 390)

    func me(_ meters: Int?) -> TrackParticipant {
        TrackParticipant(id: "me", name: "You", avatarID: "fern", distanceMeters: meters, isCurrentUser: true)
    }

    func friend(_ name: String, _ meters: Int?, availability: ProgressAvailability = .current,
                estimated: Bool = false) -> TrackParticipant {
        TrackParticipant(id: UserID("u-\(name.lowercased())"), name: name, avatarID: "sky", distanceMeters: meters,
                         isDistanceEstimated: estimated, availability: availability)
    }

    func layout(_ participants: [TrackParticipant], focus: TrackFocus = .currentUser,
                previous: TrackRange? = nil) -> TrackViewport {
        FriendTrackLayoutEngine.layout(TrackLayoutInput(participants: participants, focus: focus,
                                                        configuration: config, previousRange: previous))
    }

    func visibleNames(_ viewport: TrackViewport) -> [String] {
        viewport.characterPositions.map(\.participant.name)
    }

    /// Labels in the same lane must never overlap; every sprite stays on screen.
    func assertReadable(_ viewport: TrackViewport, file: StaticString = #filePath, line: UInt = #line) {
        let byLane = Dictionary(grouping: viewport.characterPositions, by: \.lane)
        for (_, positions) in byLane {
            let xs = positions.map(\.x).sorted()
            for (a, b) in zip(xs, xs.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b - a, config.labelWidth - 0.01, "labels overlap", file: file, line: line)
            }
        }
        for position in viewport.characterPositions {
            XCTAssertLessThan(position.lane, config.laneCount, file: file, line: line)
            XCTAssertGreaterThanOrEqual(position.exactX, viewport.plotMinX - 0.01, file: file, line: line)
            XCTAssertLessThanOrEqual(position.exactX, viewport.plotMaxX + 0.01, file: file, line: line)
        }
    }

    // MARK: Fitting

    func testNarrowSpreadFitsEveryoneInOneView() {
        let viewport = layout([me(2_400), friend("Alex", 2_800), friend("Jamie", 2_100)])
        XCTAssertEqual(Set(visibleNames(viewport)), ["You", "Alex", "Jamie"])
        XCTAssertTrue(viewport.leftOverflow.isEmpty)
        XCTAssertTrue(viewport.rightOverflow.isEmpty)
        XCTAssertTrue(viewport.isCurrentUserVisible)
        XCTAssertEqual(viewport.range, TrackRange(lower: 2_075, upper: 2_825))
        XCTAssertEqual(viewport.focusedUserID, "me")
        // Positions preserve distance order.
        XCTAssertEqual(visibleNames(viewport), ["Jamie", "You", "Alex"])
        assertReadable(viewport)
    }

    func testMinimumSpanPreventsOverZooming() {
        let viewport = layout([me(2_400), friend("Alex", 2_420)])
        XCTAssertEqual(viewport.range.span, config.minimumSpanMeters)
        assertReadable(viewport)
    }

    func testOneFriendFarAhead() {
        let viewport = layout([me(2_400), friend("Alex", 2_800), friend("Jamie", 2_100), friend("Taylor", 7_200)])
        XCTAssertEqual(Set(visibleNames(viewport)), ["You", "Alex", "Jamie"])
        XCTAssertEqual(viewport.rightOverflow.count, 1)
        let indicator = viewport.rightOverflow[0]
        XCTAssertEqual(indicator.label, "Taylor · +4.8 km")
        XCTAssertEqual(indicator.gapFromCurrentUserMeters, 4_800)
        XCTAssertEqual(indicator.direction, .ahead)
        XCTAssertFalse(indicator.isGroup)
        XCTAssertEqual(indicator.targetUserID, "u-taylor")
        XCTAssertTrue(indicator.accessibilityLabel.contains("4.8 km ahead of you"))
        // Space is reserved for the indicator on the right only.
        XCTAssertEqual(viewport.plotMaxX, 390 - 8 - 20 - 76)
        XCTAssertEqual(viewport.plotMinX, 8 + 20)
        assertReadable(viewport)
    }

    func testOneFriendFarBehind() {
        let viewport = layout([me(5_000), friend("Alex", 2_900)])
        XCTAssertEqual(visibleNames(viewport), ["You"])
        XCTAssertEqual(viewport.leftOverflow.map(\.label), ["Alex · 2.1 km behind"])
        XCTAssertEqual(viewport.leftOverflow[0].direction, .behind)
        XCTAssertTrue(viewport.rightOverflow.isEmpty)
    }

    func testMultipleFriendsAheadAreGrouped() {
        let viewport = layout([me(2_400), friend("Taylor", 7_200), friend("Robin", 9_600), friend("Alex", 2_800)])
        XCTAssertEqual(viewport.rightOverflow.count, 1)
        let group = viewport.rightOverflow[0]
        XCTAssertTrue(group.isGroup)
        XCTAssertEqual(group.label, "2 friends ahead")
        XCTAssertEqual(group.members.map(\.name), ["Taylor", "Robin"])
        XCTAssertEqual(group.targetUserID, "u-taylor", "tapping a group focuses the nearest member")
        XCTAssertEqual(viewport.rightOverflowFriends.count, 2)
    }

    func testMultipleFriendsBehindAreGrouped() {
        let viewport = layout([me(6_000), friend("Sam", 400), friend("Jamie", 2_100), friend("Pat", 1_000)])
        XCTAssertEqual(viewport.leftOverflow.count, 1)
        XCTAssertEqual(viewport.leftOverflow[0].label, "3 friends behind")
        XCTAssertEqual(viewport.leftOverflow[0].members.map(\.name), ["Jamie", "Pat", "Sam"])
        XCTAssertEqual(viewport.leftOverflow[0].targetUserID, "u-jamie")
    }

    func testLargestNearbyGroupIsPreferred() {
        // Two friends just behind and three just ahead: the window holding
        // the most people (including the user) wins.
        let viewport = layout([me(3_000), friend("A", 1_300), friend("B", 1_400),
                               friend("C", 4_500), friend("D", 4_600), friend("E", 4_700)])
        XCTAssertEqual(Set(visibleNames(viewport)), ["You", "C", "D", "E"])
        XCTAssertEqual(viewport.leftOverflow.first?.label, "2 friends behind")
        assertReadable(viewport)
    }

    // MARK: Focus

    func testFocusOnFarAheadFriendCentresThem() {
        let everyone = [me(2_400), friend("Alex", 2_800), friend("Jamie", 2_100), friend("Taylor", 7_200),
                        friend("Robin", 9_600)]
        let viewport = layout(everyone, focus: .participant("u-taylor"))
        XCTAssertEqual(viewport.focusedUserID, "u-taylor")
        XCTAssertEqual(visibleNames(viewport), ["Taylor"])
        XCTAssertFalse(viewport.isCurrentUserVisible)

        let taylor = viewport.position(for: "u-taylor")!
        XCTAssertTrue(taylor.isFocused)
        let mid = (viewport.plotMinX + viewport.plotMaxX) / 2
        XCTAssertEqual(taylor.x, mid, accuracy: 1)

        // The user gets their own indicator (not hidden in a group) for context.
        XCTAssertEqual(viewport.leftOverflow.first?.label, "You · 2.4 km")
        XCTAssertTrue(viewport.leftOverflow.first!.includesCurrentUser)
        // Alex is ahead of the user and Jamie behind, so the group isn't called "behind".
        XCTAssertEqual(viewport.leftOverflow.last?.label, "2 more friends")
        XCTAssertEqual(viewport.rightOverflow.map(\.label), ["Robin · +7.2 km"])

        XCTAssertEqual(GapText.comparison(name: "Taylor", gap: 7_200 - 2_400),
                       "Taylor has walked 4.8 km farther than you today.")
    }

    func testFocusKeepsNeighboursVisible() {
        let viewport = layout([me(2_400), friend("Taylor", 7_200), friend("Robin", 7_700), friend("Kim", 6_900)],
                              focus: .participant("u-taylor"))
        XCTAssertEqual(Set(visibleNames(viewport)), ["Taylor", "Robin", "Kim"])
        XCTAssertTrue(viewport.range.contains(7_200))
        assertReadable(viewport)
    }

    func testFocusOnUnknownOrUnavailableFriendFallsBackToMe() {
        let participants = [me(2_400), friend("Riley", nil, availability: .unavailable)]
        XCTAssertEqual(layout(participants, focus: .participant("u-nobody")).focus, .currentUser)
        XCTAssertEqual(layout(participants, focus: .participant("u-riley")).focus, .currentUser)
        XCTAssertEqual(layout(participants, focus: .participant("me")).focus, .currentUser)
    }

    func testFocusControllerTransitions() {
        let everyone = [me(2_400), friend("Taylor", 7_200)]
        var controller = TrackFocusController()
        XCTAssertFalse(controller.showsBackToMe)

        let indicator = layout(everyone, focus: controller.focus).rightOverflow[0]
        controller.select(indicator, currentUserID: "me")
        XCTAssertEqual(controller.focus, .participant("u-taylor"))
        XCTAssertTrue(controller.showsBackToMe)

        // Data refresh with Taylor still present keeps the focus.
        controller.reconcile(with: [me(2_500), friend("Taylor", 7_300)])
        XCTAssertEqual(controller.focusedFriendID, "u-taylor")

        controller.backToMe()
        XCTAssertEqual(controller.focus, .currentUser)
        XCTAssertTrue(layout(everyone, focus: controller.focus).isCurrentUserVisible)

        // Focus drops when the friend disappears.
        controller.focus(on: "u-taylor", currentUserID: "me")
        controller.reconcile(with: [me(2_500)])
        XCTAssertEqual(controller.focus, .currentUser)

        // Tapping your own "You" indicator is the same as Back to me.
        controller.focus(on: "me", currentUserID: "me")
        XCTAssertEqual(controller.focus, .currentUser)
    }

    func testPanningIsNotRecentredByDataUpdates() {
        var controller = TrackFocusController()
        let start = layout([me(2_400), friend("Alex", 2_800)])
        controller.pan(from: start.range, deltaMeters: 3_000)
        guard case .free(let center, let span) = controller.focus else { return XCTFail("expected free focus") }
        XCTAssertEqual(span, start.range.span)

        // The user keeps walking; the dragged range stays put.
        let updated = layout([me(2_600), friend("Alex", 2_900)], focus: controller.focus)
        XCTAssertEqual(updated.range.center, center)
        XCTAssertNil(updated.focusedUserID)
        XCTAssertEqual(updated.leftOverflow.first?.label, "You · 2.6 km")
        XCTAssertTrue(controller.showsBackToMe)
    }

    // MARK: Edge cases

    func testEqualDistancesStackIntoLanes() {
        let viewport = layout([me(2_000), friend("Alex", 2_000), friend("Jamie", 2_000)])
        XCTAssertEqual(viewport.characterPositions.count, 3)
        XCTAssertEqual(Set(viewport.characterPositions.map(\.lane)), [0, 1, 2])
        XCTAssertEqual(viewport.position(for: "me")?.lane, 0, "the user always gets the front row")
        XCTAssertFalse(viewport.characterPositions.contains(where: \.isNudged))
        XCTAssertEqual(Set(viewport.characterPositions.map(\.exactX)).count, 1)
        assertReadable(viewport)
    }

    func testCrowdBeyondLaneCountIsNudgedNotOverlapped() {
        let crowd = [me(2_000)] + (1...6).map { friend("F\($0)", 2_000 + $0) }
        let viewport = layout(crowd)
        XCTAssertEqual(viewport.characterPositions.count, 7)
        XCTAssertTrue(viewport.characterPositions.contains(where: \.isNudged))
        assertReadable(viewport)
    }

    func testEmptyFriendList() {
        let viewport = layout([me(0)])
        XCTAssertEqual(visibleNames(viewport), ["You"])
        XCTAssertEqual(viewport.range, TrackRange(lower: 0, upper: 500))
        XCTAssertEqual(viewport.position(for: "me")!.x, viewport.plotMinX, accuracy: 0.01)
        XCTAssertTrue(viewport.leftOverflow.isEmpty && viewport.rightOverflow.isEmpty)
    }

    func testNoParticipantsAtAll() {
        let viewport = layout([])
        XCTAssertTrue(viewport.characterPositions.isEmpty)
        XCTAssertFalse(viewport.isCurrentUserVisible)
        XCTAssertNil(viewport.focusedUserID)
    }

    func testExtremelyLargeDistances() {
        let viewport = layout([me(1_000_000_000), friend("Alex", 999_999_400), friend("Ultra", 5_000_000_000)])
        XCTAssertEqual(Set(visibleNames(viewport)), ["You", "Alex"])
        XCTAssertEqual(viewport.rightOverflow.first?.label, "Ultra · +4000000.0 km")
        assertReadable(viewport)
    }

    func testStaleFriendsArePlacedAndUnavailableAreListedOnly() {
        let viewport = layout([me(2_400), friend("Sam", 2_200, availability: .stale),
                               friend("Riley", 2_300, availability: .unavailable)])
        XCTAssertEqual(Set(visibleNames(viewport)), ["You", "Sam"])
        XCTAssertEqual(viewport.position(for: "u-sam")?.participant.availability, .stale)
        XCTAssertEqual(viewport.unavailableParticipants.map(\.name), ["Riley"])
        XCTAssertTrue(viewport.leftOverflow.isEmpty && viewport.rightOverflow.isEmpty)
    }

    func testCurrentUserWithoutDataIsNotPlaced() {
        let viewport = layout([me(nil), friend("Alex", 2_000)])
        XCTAssertFalse(viewport.isCurrentUserVisible)
        XCTAssertEqual(visibleNames(viewport), ["Alex"])
    }

    func testDuplicateParticipantsAreIgnored() {
        let viewport = layout([me(2_000), friend("Alex", 2_100), friend("Alex", 9_000)])
        XCTAssertEqual(viewport.characterPositions.count, 2)
        XCTAssertTrue(viewport.rightOverflow.isEmpty)
    }

    // MARK: Stability

    func testSmallUpdatesKeepTheRange() {
        let first = layout([me(2_400), friend("Alex", 2_800), friend("Jamie", 2_100)])
        let second = layout([me(2_450), friend("Alex", 2_800), friend("Jamie", 2_200)], previous: first.range)
        XCTAssertEqual(second.range, first.range)
        // Without hysteresis the centre would have moved.
        let fresh = layout([me(2_450), friend("Alex", 2_800), friend("Jamie", 2_200)])
        XCTAssertNotEqual(fresh.range, first.range)
    }

    func testRangeMovesWhenSomeoneWouldLeaveIt() {
        let first = layout([me(2_400), friend("Alex", 2_800)])
        let second = layout([me(2_400), friend("Alex", 3_300)], previous: first.range)
        XCTAssertTrue(second.range.contains(3_300))
        XCTAssertNotEqual(second.range, first.range)
    }

    func testLayoutIsDeterministic() {
        let participants = [me(2_400), friend("Alex", 2_800), friend("Jamie", 2_100), friend("Taylor", 7_200),
                            friend("Kim", 2_400), friend("Lee", 2_401)]
        let a = layout(participants)
        let b = layout(participants.reversed())
        XCTAssertEqual(a, b)
    }
}

final class LeaderboardTests: XCTestCase {
    func participant(_ name: String, _ meters: Int?, me: Bool = false, estimated: Bool = false,
                     availability: ProgressAvailability = .current) -> TrackParticipant {
        TrackParticipant(id: UserID(name), name: name, avatarID: "fern", distanceMeters: meters,
                         isDistanceEstimated: estimated, availability: availability, isCurrentUser: me)
    }

    func testRanksWithTiesEstimatesAndMissingData() {
        let entries = Leaderboard.rank([
            participant("Alex", 2_800), participant("You", 2_400, me: true), participant("Jamie", 2_400),
            participant("Taylor", 7_200), participant("Est", 9_000, estimated: true),
            participant("Riley", nil, availability: .unavailable), participant("Sam", 400, availability: .stale),
        ])
        XCTAssertEqual(entries.map(\.participant.name), ["Taylor", "Alex", "You", "Jamie", "Sam", "Est", "Riley"])
        XCTAssertEqual(entries.map(\.rank), [1, 2, 3, 3, 5, nil, nil])
        XCTAssertEqual(entries[5].unrankedReason, .estimatedDistance)
        XCTAssertEqual(entries[6].unrankedReason, .noDataToday)
    }
}
