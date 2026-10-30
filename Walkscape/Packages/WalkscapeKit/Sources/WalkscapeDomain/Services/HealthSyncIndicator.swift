import Foundation

/// What the Journey screen's small sync chip says about Apple Health.
public enum HealthSyncIndicator: Hashable, Sendable {
    /// Up to date as of this time.
    case synced(Date)
    /// Reading Health for the first time (or after a long gap).
    case syncing
    /// Health answered but nothing was recorded today. Not an error: it can
    /// also mean Walkscape can't read Steps, so the chip offers help on tap.
    case noStepsYet
    /// The last good update is getting old (phone locked or offline).
    case stale(Date)
    /// Health access hasn't been asked for yet.
    case needsAccess
    /// This device has no Apple Health.
    case unavailable
    /// The last read failed.
    case problem(WalkingDataError)
    case demo

    /// Shown in orange with a call to action.
    public var needsAttention: Bool {
        switch self {
        case .needsAccess, .unavailable, .problem: return true
        default: return false
        }
    }

    public static func evaluate(isDemo: Bool, authorization: WalkingAuthorizationState, status: WalkingSyncStatus,
                                now: Date) -> HealthSyncIndicator {
        if isDemo { return .demo }
        switch authorization {
        case .unavailable: return .unavailable
        case .notDetermined: return .needsAccess
        case .requested: break
        }
        let last = status.lastSuccessfulRefresh
        let freshness = status.freshness(now: now)
        switch status.phase {
        case .failed(let error):
            return .problem(error)
        case .noData:
            return .noStepsYet
        case .loading, .idle:
            // A quiet background refresh keeps the last good state on screen,
            // so the chip doesn't flicker every time the app wakes up.
            guard let last, freshness != .stale else { return .syncing }
            return .synced(last)
        case .loaded:
            guard let last else { return .syncing }
            return freshness == .stale ? .stale(last) : .synced(last)
        }
    }
}
