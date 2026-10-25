import Foundation

public enum WalkingDataSourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Apple Health on a real device.
    case appleHealth
    /// Deterministic demo data for the simulator and previews. Always labelled in the UI.
    case demo

    public var id: String { rawValue }
}

public enum WalkingAuthorizationState: String, Sendable, Hashable {
    /// Health data is not available on this device (e.g. some iPads).
    case unavailable
    /// The permission sheet has not been shown yet.
    case notDetermined
    /// The sheet was shown. HealthKit never reveals whether *read* access was
    /// granted, so "denied" looks like "no data" — the UI explains both.
    case requested
}

public enum WalkingDataError: Error, Hashable, Sendable {
    case healthDataUnavailable
    case authorizationFailed(String)
    case queryFailed(String)
}

/// Anything that can supply daily walking totals. The game logic only ever
/// sees `WalkingSnapshot`/`DailyProgress`, never HealthKit types.
public protocol WalkingDataProvider: Sendable {
    var kind: WalkingDataSourceKind { get }
    func authorizationState() async -> WalkingAuthorizationState
    func requestAuthorization() async throws
    /// Totals for local day `day` up to `now`.
    func fetchDailyTotals(for day: LocalDay, timeZone: TimeZone, now: Date) async throws -> WalkingSnapshot
}

/// How old the last successful refresh is.
public enum DataFreshness: Hashable, Sendable {
    case never
    case fresh
    case recent
    case stale

    public static func evaluate(lastRefresh: Date?, now: Date,
                                freshWithin: TimeInterval = 5 * 60,
                                staleAfter: TimeInterval = 60 * 60) -> DataFreshness {
        guard let lastRefresh else { return .never }
        let age = now.timeIntervalSince(lastRefresh)
        if age <= freshWithin { return .fresh }
        return age > staleAfter ? .stale : .recent
    }
}

/// Load state for today's walking data, independent of any UI framework.
public struct WalkingSyncStatus: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case idle
        case loading
        case loaded
        case noData
        case failed(WalkingDataError)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastSuccessfulRefresh: Date?
    public private(set) var progress: DailyProgress?

    public init() {}

    public mutating func beginRefresh() {
        phase = .loading
    }

    /// Records a successful fetch. A snapshot for a new day replaces the old
    /// day's numbers; an older snapshot arriving late is ignored.
    public mutating func finish(with snapshot: WalkingSnapshot, userID: UserID) {
        if let progress, snapshot.day < progress.localDate {
            phase = .loaded
            return
        }
        lastSuccessfulRefresh = snapshot.fetchedAt
        progress = DailyProgress(snapshot: snapshot, userID: userID)
        phase = snapshot.hasAnyData ? .loaded : .noData
    }

    public mutating func fail(_ error: WalkingDataError) {
        phase = .failed(error)
    }

    /// Clears yesterday's numbers after local midnight, before the next fetch lands.
    public mutating func rollOver(to today: LocalDay) {
        guard let progress, progress.localDate < today else { return }
        self.progress = nil
        phase = .idle
    }

    public func freshness(now: Date) -> DataFreshness {
        DataFreshness.evaluate(lastRefresh: lastSuccessfulRefresh, now: now)
    }
}
