import Foundation

/// Deterministic walking data for the simulator, previews and tests.
/// The UI always labels it as demo data — it is never presented as Health data.
public final class MockWalkingDataProvider: WalkingDataProvider, @unchecked Sendable {
    public enum Scenario: Hashable, Sendable {
        /// Fixed totals (plus any simulated walking).
        case fixed(steps: Int, meters: Int)
        /// Totals grow through the day toward `targetSteps` by evening.
        case typicalDay(targetSteps: Int)
        /// Steps but no distance samples (exercises estimation).
        case stepsOnly(steps: Int)
        case noData
        case failing
    }

    public let kind: WalkingDataSourceKind = .demo
    private let lock = NSLock()
    private var scenario: Scenario
    private var extraMeters = 0
    private var authorization: WalkingAuthorizationState = .requested

    /// Matches the product brief's example: 2.4 km into the Pine Forest.
    public init(scenario: Scenario = .fixed(steps: 3_180, meters: 2_400)) {
        self.scenario = scenario
    }

    public func setScenario(_ scenario: Scenario) {
        lock.withLock {
            self.scenario = scenario
            extraMeters = 0
        }
    }

    /// Developer tool: pretend to walk a little further.
    public func simulateWalk(meters: Int) {
        lock.withLock { extraMeters += max(0, meters) }
    }

    public func authorizationState() async -> WalkingAuthorizationState {
        lock.withLock { authorization }
    }

    public func requestAuthorization() async throws {
        lock.withLock { authorization = .requested }
    }

    public func fetchDailyTotals(for day: LocalDay, timeZone: TimeZone, now: Date) async throws -> WalkingSnapshot {
        let (scenario, extra) = lock.withLock { (self.scenario, extraMeters) }
        let extraSteps = Int(Double(extra) / 0.755)
        func snapshot(_ steps: Int?, _ meters: Int?) -> WalkingSnapshot {
            WalkingSnapshot(day: day, timeZoneIdentifier: timeZone.identifier, steps: steps,
                            recordedDistanceMeters: meters, fetchedAt: now)
        }
        switch scenario {
        case .fixed(let steps, let meters):
            return snapshot(steps + extraSteps, meters + extra)
        case .typicalDay(let target):
            let interval = day.interval(in: timeZone)
            let fraction = min(1, max(0, now.timeIntervalSince(interval.start) / interval.duration))
            // Little walking before 7am, most of it during the day.
            let active = min(1, max(0, (fraction - 0.29) / 0.55))
            let eased = active * active * (3 - 2 * active)
            let steps = Int(Double(target) * eased)
            return snapshot(steps + extraSteps, Int(Double(steps) * 0.755) + extra)
        case .stepsOnly(let steps):
            return snapshot(steps + extraSteps, nil)
        case .noData:
            return extra > 0 ? snapshot(extraSteps, extra) : snapshot(nil, nil)
        case .failing:
            throw WalkingDataError.queryFailed("Simulated query failure")
        }
    }
}
