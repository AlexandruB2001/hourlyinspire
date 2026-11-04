import XCTest
@testable import WalkscapeDomain

final class BetaUpdateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlyANewerBuildIsOffered() {
        let update = BetaUpdate(build: 26, notes: "New things")
        XCTAssertTrue(update.shouldPrompt(currentBuild: 25, snoozedBuild: nil, snoozedUntil: nil, now: now))
        XCTAssertFalse(update.shouldPrompt(currentBuild: 26, snoozedBuild: nil, snoozedUntil: nil, now: now))
        XCTAssertFalse(update.shouldPrompt(currentBuild: 27, snoozedBuild: nil, snoozedUntil: nil, now: now))
    }

    func testLaterWaitsADayButNotForTheNextBuild() {
        let update = BetaUpdate(build: 26, notes: "")
        let until = now.addingTimeInterval(BetaUpdate.snooze)
        XCTAssertFalse(update.shouldPrompt(currentBuild: 25, snoozedBuild: 26, snoozedUntil: until, now: now))
        XCTAssertTrue(update.shouldPrompt(currentBuild: 25, snoozedBuild: 26, snoozedUntil: until, now: until.addingTimeInterval(1)))
        XCTAssertTrue(BetaUpdate(build: 27, notes: "").shouldPrompt(currentBuild: 25, snoozedBuild: 26, snoozedUntil: until, now: now),
                      "a newer build asks again straight away")
    }

    func testDecodesTheSiteFile() throws {
        let update = try JSONDecoder().decode(BetaUpdate.self, from: Data(#"{"build": 25, "notes": "Daily chest"}"#.utf8))
        XCTAssertEqual(update, BetaUpdate(build: 25, notes: "Daily chest"))
    }
}
