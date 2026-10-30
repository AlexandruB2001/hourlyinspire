import XCTest
@testable import WalkscapeDomain

final class HealthSyncIndicatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day = LocalDay(year: 2027, month: 1, day: 15)

    func indicator(_ status: WalkingSyncStatus, authorization: WalkingAuthorizationState = .requested,
                   isDemo: Bool = false, at time: Date? = nil) -> HealthSyncIndicator {
        HealthSyncIndicator.evaluate(isDemo: isDemo, authorization: authorization, status: status, now: time ?? now)
    }

    func loaded(steps: Int?, at time: Date) -> WalkingSyncStatus {
        var status = WalkingSyncStatus()
        status.beginRefresh()
        status.finish(with: WalkingSnapshot(day: day, timeZoneIdentifier: "UTC", steps: steps,
                                            recordedDistanceMeters: steps.map { $0 / 2 }, fetchedAt: time),
                      userID: "me")
        return status
    }

    func testPermissionStatesNeedAttention() {
        XCTAssertEqual(indicator(WalkingSyncStatus(), authorization: .notDetermined), .needsAccess)
        XCTAssertEqual(indicator(WalkingSyncStatus(), authorization: .unavailable), .unavailable)
        XCTAssertTrue(HealthSyncIndicator.needsAccess.needsAttention)
        XCTAssertEqual(indicator(WalkingSyncStatus(), isDemo: true), .demo)
    }

    func testSyncingThenSynced() {
        var status = WalkingSyncStatus()
        status.beginRefresh()
        XCTAssertEqual(indicator(status), .syncing, "the first read shows progress")
        status = loaded(steps: 4_000, at: now)
        XCTAssertEqual(indicator(status), .synced(now))
        // A background refresh of fresh data keeps showing "synced" instead of flickering.
        status.beginRefresh()
        XCTAssertEqual(indicator(status, at: now.addingTimeInterval(120)), .synced(now))
    }

    func testNoStepsIsNotAnError() {
        let status = loaded(steps: nil, at: now)
        XCTAssertEqual(indicator(status), .noStepsYet)
        XCTAssertFalse(HealthSyncIndicator.noStepsYet.needsAttention)
    }

    func testOldDataIsStaleAndAFailureIsAProblem() {
        var status = loaded(steps: 4_000, at: now)
        let later = now.addingTimeInterval(2 * 60 * 60)
        XCTAssertEqual(indicator(status, at: later), .stale(now))
        status.beginRefresh()
        XCTAssertEqual(indicator(status, at: later), .syncing, "refreshing old data shows progress")
        status.fail(.queryFailed("locked"))
        XCTAssertEqual(indicator(status, at: later), .problem(.queryFailed("locked")))
        XCTAssertTrue(indicator(status, at: later).needsAttention)
    }
}
