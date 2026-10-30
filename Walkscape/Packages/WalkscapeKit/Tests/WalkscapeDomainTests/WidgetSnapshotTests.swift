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
}
