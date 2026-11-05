import Foundation

/// What the Apple Watch app and its complications show: the phone's last
/// snapshot (outfit, companion, totals) brought up to date with today's walk
/// as the watch reads it from Apple Health. Either side may be missing.
public struct WatchGlance: Hashable, Sendable {
    public var day: LocalDay
    public var todayMeters: Int
    public var todaySteps: Int?
    /// Distance estimated from steps (no recorded distance yet today).
    public var isEstimated: Bool
    /// Lifetime distance; nil until the phone has sent a snapshot.
    public var totalMeters: Int?
    public var zone: ZoneProgress
    /// The phone's look, for drawing the walker and companion.
    public var snapshot: WidgetSnapshot?

    /// 0...1 through the current kilometre of today's walk.
    public var kilometreFraction: Double { Double(todayMeters % 1_000) / 1_000 }

    /// Combines the phone's `snapshot` with the watch's own reading of today.
    /// Today's distance is whichever is further along (both read the same
    /// Apple Health data, one may simply be more recent).
    public static func make(snapshot: WidgetSnapshot?, live: DailyProgress?, today: LocalDay,
                            engine: ZoneProgressionEngine = ZoneProgressionEngine()) -> WatchGlance {
        let phone = snapshot?.showing(on: today)
        let phoneToday = phone?.day == today ? phone : nil
        let live = live?.localDate == today ? live : nil
        let liveMeters = live?.distanceMeters ?? 0
        let phoneMeters = phoneToday?.todayMeters ?? 0
        let meters = max(liveMeters, phoneMeters)
        let steps: Int? = switch (live?.steps, phoneToday?.todaySteps) {
        case let (a?, b?): max(a, b)
        case let (a?, nil): a
        case let (nil, b?): b
        case (nil, nil): nil
        }
        return WatchGlance(day: today, todayMeters: meters, todaySteps: steps,
                           isEstimated: liveMeters >= phoneMeters && live?.isEstimated == true,
                           totalMeters: phone.map { $0.totalMeters + max(0, meters - phoneMeters) },
                           zone: engine.progress(forMeters: meters), snapshot: phone)
    }
}
