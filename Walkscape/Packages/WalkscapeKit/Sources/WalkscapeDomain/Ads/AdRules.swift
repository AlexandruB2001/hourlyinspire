import Foundation

/// How often ads may appear. Walking stays the main way to earn coins:
/// a full day of rewarded ads is worth less than a 5 km walk.
public struct AdRules: Hashable, Sendable {
    /// Coins for watching one rewarded ad to the end.
    public var rewardedCoins: Int
    /// Rewarded ads that pay out per local day.
    public var rewardedPerDay: Int
    /// Minimum time between two app-open ads.
    public var appOpenCooldown: TimeInterval
    /// New players see no app-open ads for this many days after first launch.
    public var gracePeriodDays: Int
    /// Coming back after less time than this (a quick glance) never shows an app-open ad.
    public var minimumTimeAway: TimeInterval

    public init(rewardedCoins: Int = 15, rewardedPerDay: Int = 3, appOpenCooldown: TimeInterval = 4 * 60 * 60,
                gracePeriodDays: Int = 5, minimumTimeAway: TimeInterval = 60) {
        self.rewardedCoins = rewardedCoins
        self.rewardedPerDay = rewardedPerDay
        self.appOpenCooldown = appOpenCooldown
        self.gracePeriodDays = gracePeriodDays
        self.minimumTimeAway = minimumTimeAway
    }

    public static let standard = AdRules()
}

/// Ad frequency bookkeeping for this device. Shared across data sources, so
/// switching to demo walking never resets the daily rewarded-ad limit.
public struct AdState: Codable, Hashable, Sendable {
    public private(set) var firstLaunch: Date
    public private(set) var lastAppOpenAd: Date?
    /// The local day `rewardedToday` belongs to.
    public private(set) var rewardedDay: LocalDay?
    public private(set) var rewardedToday: Int

    public init(firstLaunch: Date) {
        self.firstLaunch = firstLaunch
        lastAppOpenAd = nil
        rewardedDay = nil
        rewardedToday = 0
    }

    // MARK: App-open ads

    /// Whether an app-open ad may be shown now.
    /// - Parameters:
    ///   - timeAway: how long the app was in the background, or nil for a cold launch.
    ///   - isOnboarded: false while the player is still choosing a companion.
    public func mayShowAppOpenAd(now: Date, timeAway: TimeInterval?, isOnboarded: Bool,
                                 rules: AdRules = .standard) -> Bool {
        guard isOnboarded else { return false }
        guard now.timeIntervalSince(firstLaunch) >= TimeInterval(rules.gracePeriodDays) * 24 * 60 * 60 else { return false }
        if let timeAway, timeAway < rules.minimumTimeAway { return false }
        if let lastAppOpenAd, now.timeIntervalSince(lastAppOpenAd) < rules.appOpenCooldown { return false }
        return true
    }

    public mutating func recordAppOpenAd(at date: Date) {
        lastAppOpenAd = date
    }

    // MARK: Rewarded ads

    public func rewardedAdsLeft(on day: LocalDay, rules: AdRules = .standard) -> Int {
        rewardedDay == day ? max(0, rules.rewardedPerDay - rewardedToday) : rules.rewardedPerDay
    }

    /// Counts a finished rewarded ad. Returns the coins to pay, or nil when
    /// today's limit is already used up.
    public mutating func recordRewardedAd(on day: LocalDay, rules: AdRules = .standard) -> Int? {
        guard rewardedAdsLeft(on: day, rules: rules) > 0 else { return nil }
        if rewardedDay != day {
            rewardedDay = day
            rewardedToday = 0
        }
        rewardedToday += 1
        return rules.rewardedCoins
    }
}
