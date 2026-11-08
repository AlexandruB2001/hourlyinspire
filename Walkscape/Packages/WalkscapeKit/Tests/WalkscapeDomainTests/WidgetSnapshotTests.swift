import XCTest
@testable import WalkscapeDomain

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTripsThroughTheSharedStore() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.preview)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), .preview)
    }

    func testTodayResetsAtMidnightButTotalsStay() {
        let snapshot = WidgetSnapshot.preview
        XCTAssertEqual(snapshot.showing(on: snapshot.day), snapshot)
        let tomorrow = snapshot.showing(on: snapshot.day.adding(days: 1))
        XCTAssertEqual(tomorrow.todayMeters, 0)
        XCTAssertNil(tomorrow.todaySteps)
        XCTAssertEqual(tomorrow.zoneName, "Sunny Meadow")
        XCTAssertEqual(tomorrow.metersToNextZone, 1_000)
        XCTAssertEqual(tomorrow.totalMeters, snapshot.totalMeters)
        XCTAssertEqual(tomorrow.companionKilometres, snapshot.companionKilometres)
        XCTAssertEqual(snapshot.showing(on: snapshot.day.adding(days: -1)), snapshot, "an older clock changes nothing")
    }

    func testWeekTotalRunsMondayToTodayWithTheLiveNumber() {
        let wednesday = LocalDay(year: 2026, month: 11, day: 4)
        let best = ["2026-11-01": 9_000, "2026-11-02": 1_000, "2026-11-03": 2_000, "2026-11-04": 500]
        XCTAssertEqual(WidgetSnapshot.weekTotal(dailyBestMeters: best, today: wednesday, todayMeters: 3_000), 6_000, "Sunday is last week")
        XCTAssertEqual(WidgetSnapshot.weekTotal(dailyBestMeters: best, today: wednesday, todayMeters: 100), 3_500, "never below the saved best")
    }

    func testWeekResetsOnMondayOnly() {
        var snapshot = WidgetSnapshot.preview
        snapshot.day = LocalDay(year: 2026, month: 11, day: 7) // Saturday
        XCTAssertEqual(snapshot.showing(on: snapshot.day.adding(days: 1)).weekMeters, snapshot.weekMeters)
        XCTAssertEqual(snapshot.showing(on: snapshot.day.adding(days: 2)).weekMeters, 0)
    }

    func testSnapshotsFromOlderBuildsStillLoad() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetSnapshot.preview)) as! [String: Any]
        json["weekMeters"] = nil
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.weekMeters)
    }
}
