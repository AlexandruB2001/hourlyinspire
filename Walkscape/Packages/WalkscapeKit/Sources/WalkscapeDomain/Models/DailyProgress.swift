import Foundation

/// Where a distance value came from. Estimated distances are always labelled
/// in the UI and never ranked against recorded distances.
public enum DistanceSource: String, Codable, Sendable, Hashable {
    /// Apple Health walking + running distance.
    case recorded
    /// Derived from steps with `StepDistanceEstimator` because no distance was recorded.
    case estimatedFromSteps
    /// Neither distance nor steps were available.
    case unavailable
}

/// One user's aggregate walking totals for one local day.
/// Distances are integer metres — the canonical unit across Walkscape.
public struct DailyProgress: Codable, Hashable, Sendable {
    public var userID: UserID
    public var localDate: LocalDay
    public var timeZoneIdentifier: String
    public var steps: Int
    public var distanceMeters: Int
    public var distanceSource: DistanceSource
    public var updatedAt: Date

    public init(userID: UserID, localDate: LocalDay, timeZoneIdentifier: String, steps: Int,
                distanceMeters: Int, distanceSource: DistanceSource, updatedAt: Date) {
        self.userID = userID
        self.localDate = localDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.steps = max(0, steps)
        self.distanceMeters = max(0, distanceMeters)
        self.distanceSource = distanceSource
        self.updatedAt = updatedAt
    }

    /// Builds a progress model from raw provider totals.
    ///
    /// Recorded distance always wins. When only steps exist and `allowEstimate`
    /// is true, distance is estimated and marked `.estimatedFromSteps`.
    public init(snapshot: WalkingSnapshot, userID: UserID, allowEstimate: Bool = true,
                strideMeters: Double = StepDistanceEstimator.defaultStrideMeters) {
        let steps = snapshot.steps ?? 0
        let distance: Int
        let source: DistanceSource
        if let recorded = snapshot.recordedDistanceMeters {
            distance = recorded
            source = .recorded
        } else if allowEstimate, steps > 0 {
            distance = StepDistanceEstimator.estimatedMeters(steps: steps, strideMeters: strideMeters)
            source = .estimatedFromSteps
        } else {
            distance = 0
            source = snapshot.steps == nil ? .unavailable : .recorded
        }
        self.init(userID: userID, localDate: snapshot.day, timeZoneIdentifier: snapshot.timeZoneIdentifier,
                  steps: steps, distanceMeters: distance, distanceSource: source, updatedAt: snapshot.fetchedAt)
    }

    public var isEstimated: Bool { distanceSource == .estimatedFromSteps }
}

/// Raw daily totals returned by a `WalkingDataProvider`.
/// `nil` means "no samples", which is different from zero.
public struct WalkingSnapshot: Hashable, Sendable {
    public var day: LocalDay
    public var timeZoneIdentifier: String
    public var steps: Int?
    public var recordedDistanceMeters: Int?
    public var fetchedAt: Date

    public init(day: LocalDay, timeZoneIdentifier: String, steps: Int?, recordedDistanceMeters: Int?, fetchedAt: Date) {
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
        self.steps = steps
        self.recordedDistanceMeters = recordedDistanceMeters
        self.fetchedAt = fetchedAt
    }

    public var hasAnyData: Bool { steps != nil || recordedDistanceMeters != nil }
}

/// Estimates distance from steps when Apple Health has no distance samples.
///
/// Assumption: an average adult walking stride of 0.762 m (2.5 ft). Real
/// stride varies with height and pace, which is why estimated distance is
/// always labelled and excluded from rankings.
public enum StepDistanceEstimator {
    public static let defaultStrideMeters = 0.762

    public static func estimatedMeters(steps: Int, strideMeters: Double = defaultStrideMeters) -> Int {
        guard steps > 0, strideMeters > 0 else { return 0 }
        return Int((Double(steps) * strideMeters).rounded(.down))
    }
}
