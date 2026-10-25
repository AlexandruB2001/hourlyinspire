import XCTest
@testable import WalkscapeDomain

final class WalkingDataTests: XCTestCase {
    let london = TimeZone(identifier: "Europe/London")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // MARK: Local days

    func testLocalDayDependsOnTimeZone() {
        let instant = date("2026-10-25T20:30:00Z")
        XCTAssertEqual(LocalDay(date: instant, timeZone: london).isoString, "2026-10-25")
        XCTAssertEqual(LocalDay(date: instant, timeZone: tokyo).isoString, "2026-10-26")
    }

    func testLocalDayResetsAtMidnight() {
        // London is on GMT after the DST change on 25 Oct 2026.
        let before = LocalDay(date: date("2026-10-26T23:59:59Z"), timeZone: london)
        let after = LocalDay(date: date("2026-10-27T00:00:00Z"), timeZone: london)
        XCTAssertEqual(before.isoString, "2026-10-26")
        XCTAssertEqual(after.isoString, "2026-10-27")
        XCTAssertLessThan(before, after)
    }

    func testDSTDayIntervalIs25Hours() {
        // Clocks go back on Sunday 25 October 2026 in the UK.
        let interval = LocalDay(year: 2026, month: 10, day: 25).interval(in: london)
        XCTAssertEqual(interval.duration, 25 * 3_600)
        XCTAssertEqual(interval.start, date("2026-10-24T23:00:00Z"))
    }

    func testLocalDayAddingAndParsing() {
        let day = LocalDay(year: 2026, month: 12, day: 31)
        XCTAssertEqual(day.adding(days: 1).isoString, "2027-01-01")
        XCTAssertEqual(LocalDay(isoString: "2026-02-28")?.adding(days: 1).isoString, "2026-03-01")
        XCTAssertNil(LocalDay(isoString: "2026-13-01"))
        XCTAssertNil(LocalDay(isoString: "nope"))
    }

    // MARK: Distance sources

    func testRecordedDistanceWins() {
        let snapshot = WalkingSnapshot(day: .init(year: 2026, month: 10, day: 25), timeZoneIdentifier: "UTC",
                                       steps: 3_000, recordedDistanceMeters: 2_100, fetchedAt: Date())
        let progress = DailyProgress(snapshot: snapshot, userID: "me")
        XCTAssertEqual(progress.distanceMeters, 2_100)
        XCTAssertEqual(progress.distanceSource, .recorded)
    }

    func testStepsOnlyIsEstimatedAndLabelled() {
        let snapshot = WalkingSnapshot(day: .init(year: 2026, month: 10, day: 25), timeZoneIdentifier: "UTC",
                                       steps: 1_000, recordedDistanceMeters: nil, fetchedAt: Date())
        let progress = DailyProgress(snapshot: snapshot, userID: "me")
        XCTAssertEqual(progress.distanceMeters, 762)
        XCTAssertTrue(progress.isEstimated)

        let strict = DailyProgress(snapshot: snapshot, userID: "me", allowEstimate: false)
        XCTAssertEqual(strict.distanceMeters, 0)
        XCTAssertEqual(strict.distanceSource, .recorded)
    }

    func testNoDataIsUnavailableNotZeroRecorded() {
        let snapshot = WalkingSnapshot(day: .init(year: 2026, month: 10, day: 25), timeZoneIdentifier: "UTC",
                                       steps: nil, recordedDistanceMeters: nil, fetchedAt: Date())
        XCTAssertEqual(DailyProgress(snapshot: snapshot, userID: "me").distanceSource, .unavailable)
    }

    // MARK: Sync status

    func testSyncStatusPhasesAndFreshness() {
        var status = WalkingSyncStatus()
        let now = date("2026-10-25T12:00:00Z")
        XCTAssertEqual(status.freshness(now: now), .never)
        status.beginRefresh()
        XCTAssertEqual(status.phase, .loading)
        let day = LocalDay(year: 2026, month: 10, day: 25)
        status.finish(with: WalkingSnapshot(day: day, timeZoneIdentifier: "UTC", steps: 10, recordedDistanceMeters: 8,
                                            fetchedAt: now), userID: "me")
        XCTAssertEqual(status.phase, .loaded)
        XCTAssertEqual(status.freshness(now: now.addingTimeInterval(60)), .fresh)
        XCTAssertEqual(status.freshness(now: now.addingTimeInterval(30 * 60)), .recent)
        XCTAssertEqual(status.freshness(now: now.addingTimeInterval(2 * 3_600)), .stale)

        // A failure keeps the last good numbers and refresh time.
        status.fail(.queryFailed("boom"))
        XCTAssertEqual(status.progress?.distanceMeters, 8)
        XCTAssertEqual(status.lastSuccessfulRefresh, now)
    }

    func testSyncStatusIgnoresLateSnapshotAndRollsOver() {
        var status = WalkingSyncStatus()
        let today = LocalDay(year: 2026, month: 10, day: 25)
        status.finish(with: WalkingSnapshot(day: today, timeZoneIdentifier: "UTC", steps: 100, recordedDistanceMeters: 80,
                                            fetchedAt: Date()), userID: "me")
        status.finish(with: WalkingSnapshot(day: today.adding(days: -1), timeZoneIdentifier: "UTC", steps: 9_000,
                                            recordedDistanceMeters: 7_000, fetchedAt: Date()), userID: "me")
        XCTAssertEqual(status.progress?.distanceMeters, 80)

        status.rollOver(to: today.adding(days: 1))
        XCTAssertNil(status.progress)
    }

    func testRestoreAndCancel() {
        var status = WalkingSyncStatus()
        let saved = DailyProgress(userID: "me", localDate: .init(year: 2026, month: 10, day: 25), timeZoneIdentifier: "UTC",
                                  steps: 100, distanceMeters: 70, distanceSource: .recorded,
                                  updatedAt: date("2026-10-25T08:00:00Z"))
        status.restore(saved)
        XCTAssertEqual(status.progress, saved)
        XCTAssertEqual(status.lastSuccessfulRefresh, saved.updatedAt)
        XCTAssertEqual(status.freshness(now: date("2026-10-25T12:00:00Z")), .stale)
        status.beginRefresh()
        status.cancelRefresh()
        XCTAssertEqual(status.phase, .loaded)
    }

    func testFriendAvailability() {
        let now = date("2026-10-25T12:00:00Z")
        let today = LocalDay(year: 2026, month: 10, day: 25)
        XCTAssertEqual(ProgressAvailability.evaluate(localDate: today, updatedAt: now.addingTimeInterval(-600),
                                                     today: today, now: now), .current)
        XCTAssertEqual(ProgressAvailability.evaluate(localDate: today, updatedAt: now.addingTimeInterval(-4 * 3_600),
                                                     today: today, now: now), .stale)
        XCTAssertEqual(ProgressAvailability.evaluate(localDate: today.adding(days: -1), updatedAt: now,
                                                     today: today, now: now), .unavailable)
        XCTAssertEqual(ProgressAvailability.evaluate(localDate: nil, updatedAt: nil, today: today, now: now), .unavailable)
    }

    // MARK: Mock provider

    func testMockProviderSimulatedWalkAndScenarios() async throws {
        let provider = MockWalkingDataProvider()
        let day = LocalDay(year: 2026, month: 10, day: 25)
        let first = try await provider.fetchDailyTotals(for: day, timeZone: london, now: Date())
        XCTAssertEqual(first.recordedDistanceMeters, 2_400)
        provider.simulateWalk(meters: 700)
        let second = try await provider.fetchDailyTotals(for: day, timeZone: london, now: Date())
        XCTAssertEqual(second.recordedDistanceMeters, 3_100)

        provider.setScenario(.failing)
        do {
            _ = try await provider.fetchDailyTotals(for: day, timeZone: london, now: Date())
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? WalkingDataError, .queryFailed("Simulated query failure"))
        }
    }

    // MARK: Formatting

    func testDistanceFormatting() {
        let en = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(DistanceFormatting.kilometres(999, locale: en), "0.9 km")
        XCTAssertEqual(DistanceFormatting.kilometres(2_400, locale: en), "2.4 km")
        XCTAssertEqual(DistanceFormatting.kilometres(2_499, locale: en), "2.4 km")
        XCTAssertEqual(DistanceFormatting.remaining(1, locale: en), "10 m")
        XCTAssertEqual(DistanceFormatting.remaining(995, locale: en), "1.0 km")
        XCTAssertEqual(DistanceFormatting.remaining(1_201, locale: en), "1.3 km")
        XCTAssertEqual(DistanceFormatting.signedGap(4_800, locale: en), "+4.8 km")
        XCTAssertEqual(DistanceFormatting.signedGap(-2_140, locale: en), "−2.1 km")
        XCTAssertEqual(DistanceFormatting.signedGap(20, locale: en), "±0.0 km")
        XCTAssertEqual(DistanceFormatting.kilometres(2_400, locale: Locale(identifier: "de_DE")), "2,4 km")
    }
}
