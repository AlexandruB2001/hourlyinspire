import Foundation
import WalkscapeDomain

/// Uploads today's totals, skipping uploads that wouldn't change anything.
///
/// The server's upsert is idempotent anyway; this just avoids needless
/// requests when HealthKit refreshes return the same numbers.
public actor DailyProgressSyncer {
    public enum Outcome: Hashable, Sendable {
        case uploaded
        /// Same totals as the last successful upload.
        case skippedUnchanged
        /// No real data to share (e.g. Health returned nothing).
        case skippedUnavailable
    }

    private struct Fingerprint: Hashable {
        let day: LocalDay
        let steps: Int
        let meters: Int
        let source: DistanceSource
    }

    private let api: SupabaseAPI
    private var lastUploaded: Fingerprint?

    public init(api: SupabaseAPI) {
        self.api = api
    }

    @discardableResult
    public func sync(_ progress: DailyProgress) async throws -> Outcome {
        guard progress.distanceSource != .unavailable else { return .skippedUnavailable }
        let fingerprint = Fingerprint(day: progress.localDate, steps: progress.steps,
                                      meters: progress.distanceMeters, source: progress.distanceSource)
        if fingerprint == lastUploaded { return .skippedUnchanged }

        struct Params: Encodable {
            let p_local_date: String
            let p_time_zone: String
            let p_steps: Int
            let p_distance_meters: Int
            let p_distance_source: String
            let p_client_updated_at: Date
        }
        let params = Params(p_local_date: progress.localDate.isoString, p_time_zone: progress.timeZoneIdentifier,
                            p_steps: progress.steps, p_distance_meters: progress.distanceMeters,
                            p_distance_source: progress.distanceSource.rawValue, p_client_updated_at: progress.updatedAt)
        let _: IgnoredResult = try await api.call("upsert_daily_progress", params)
        lastUploaded = fingerprint
        return .uploaded
    }

    /// Forget what was uploaded (e.g. after signing in as someone else).
    public func reset() {
        lastUploaded = nil
    }
}
