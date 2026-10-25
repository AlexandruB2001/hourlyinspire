import Foundation
import HealthKit
import WalkscapeDomain

/// Reads today's step count and walking + running distance from Apple Health.
///
/// - Read-only: requests no write access.
/// - Uses cumulative-sum statistics queries, which let HealthKit merge
///   overlapping samples (e.g. iPhone + Apple Watch) instead of adding them twice.
/// - Day boundaries come from `LocalDay`, i.e. local midnight in the given time zone.
final class HealthKitWalkingDataProvider: WalkingDataProvider, @unchecked Sendable {
    let kind: WalkingDataSourceKind = .appleHealth

    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private var readTypes: Set<HKObjectType> { [stepType, distanceType] }

    private let lock = NSLock()
    private var observerQueries: [HKObserverQuery] = []

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationState() async -> WalkingAuthorizationState {
        guard Self.isAvailable else { return .unavailable }
        do {
            switch try await store.statusForAuthorizationRequest(toShare: [], read: readTypes) {
            case .unnecessary: return .requested
            case .shouldRequest, .unknown: return .notDetermined
            @unknown default: return .notDetermined
            }
        } catch {
            return .notDetermined
        }
    }

    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw WalkingDataError.healthDataUnavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            throw WalkingDataError.authorizationFailed(error.localizedDescription)
        }
    }

    func fetchDailyTotals(for day: LocalDay, timeZone: TimeZone, now: Date) async throws -> WalkingSnapshot {
        guard Self.isAvailable else { throw WalkingDataError.healthDataUnavailable }
        let interval = day.interval(in: timeZone)
        let end = min(max(now, interval.start), interval.end)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: end, options: .strictStartDate)

        async let steps = cumulativeSum(of: stepType, unit: .count(), predicate: predicate)
        async let meters = cumulativeSum(of: distanceType, unit: .meter(), predicate: predicate)
        let (stepTotal, meterTotal) = try await (steps, meters)

        return WalkingSnapshot(day: day, timeZoneIdentifier: timeZone.identifier,
                               steps: stepTotal.map { Int($0.rounded()) },
                               recordedDistanceMeters: meterTotal.map { Int($0.rounded()) },
                               fetchedAt: now)
    }

    /// `nil` when there are no samples in the range (distinct from zero).
    private func cumulativeSum(of type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async throws -> Double? {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum)
        do {
            return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            throw WalkingDataError.queryFailed("Health data is unavailable while your iPhone is locked.")
        } catch {
            throw WalkingDataError.queryFailed(error.localizedDescription)
        }
    }

    /// Calls `onChange` whenever new step or distance samples arrive, including
    /// in the background (hourly at most; iOS decides the exact timing).
    /// Requires the HealthKit Background Delivery entitlement.
    func startObservingChanges(_ onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard Self.isAvailable, observerQueries.isEmpty else { return }
        for type in [stepType, distanceType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil { onChange() }
                completion()
            }
            store.execute(query)
            observerQueries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }
}
