import XCTest
@testable import WalkscapeDomain

final class WatchGlanceTests: XCTestCase {
    let today = LocalDay(year: 2026, month: 11, day: 4)

    func live(_ meters: Int, steps: Int = 0, estimated: Bool = false, day: LocalDay? = nil) -> DailyProgress {
        DailyProgress(userID: "me", localDate: day ?? today, timeZoneIdentifier: "Europe/London", steps: steps,
                      distanceMeters: meters, distanceSource: estimated ? .estimatedFromSteps : .recorded, updatedAt: Date())
    }

    func phone(today meters: Int, total: Int, day: LocalDay? = nil) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot.preview
        snapshot.day = day ?? today
        snapshot.todayMeters = meters
        snapshot.todaySteps = meters
        snapshot.totalMeters = total
        return snapshot
    }

    func testTheWatchCatchesUpOnThePhone() {
        let glance = WatchGlance.make(snapshot: phone(today: 2_000, total: 50_000), live: live(3_400, steps: 4_500), today: today)
        XCTAssertEqual(glance.todayMeters, 3_400, "the watch's newer reading wins")
        XCTAssertEqual(glance.todaySteps, 4_500)
        XCTAssertEqual(glance.totalMeters, 51_400, "the total moves on with today's extra walking")
        XCTAssertEqual(glance.zone.distanceMeters, 3_400)
        XCTAssertEqual(glance.kilometreFraction, 0.4, accuracy: 0.0001)
    }

    func testAnOlderWatchReadingNeverGoesBackwards() {
        let glance = WatchGlance.make(snapshot: phone(today: 5_000, total: 60_000), live: live(4_000), today: today)
        XCTAssertEqual(glance.todayMeters, 5_000)
        XCTAssertEqual(glance.totalMeters, 60_000)
    }

    func testYesterdaysPhoneSnapshotStartsAFreshDay() {
        let glance = WatchGlance.make(snapshot: phone(today: 9_000, total: 70_000, day: today.adding(days: -1)),
                                      live: live(1_200), today: today)
        XCTAssertEqual(glance.todayMeters, 1_200)
        XCTAssertEqual(glance.totalMeters, 71_200)
        XCTAssertNotNil(glance.snapshot, "the outfit and companion still come from the phone")
    }

    func testWithoutThePhoneTheWatchShowsTodayOnly() {
        let glance = WatchGlance.make(snapshot: nil, live: live(800, steps: 1_050, estimated: true), today: today)
        XCTAssertEqual(glance.todayMeters, 800)
        XCTAssertTrue(glance.isEstimated)
        XCTAssertNil(glance.totalMeters)
        XCTAssertNil(glance.snapshot)
        XCTAssertEqual(glance.zone.currentZone, ZoneCatalog.standard.zones[0])
    }

    func testNothingYetIsAFreshStart() {
        let glance = WatchGlance.make(snapshot: nil, live: live(500, day: today.adding(days: -1)), today: today)
        XCTAssertEqual(glance.todayMeters, 0, "yesterday's reading doesn't count today")
        XCTAssertNil(glance.todaySteps)
    }
}
