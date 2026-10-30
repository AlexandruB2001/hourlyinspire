import Foundation

/// How lifetime Explorer XP is earned. Separate from coins: XP never gets spent.
public struct ExplorerRules: Hashable, Sendable {
    public var xpPerKilometre: Int
    /// Distance above this in one day earns no extra XP, so a huge day can't skip levels.
    public var dailyXPCapMeters: Int
    public var xpPerZone: Int
    public var xpPerRelic: Int
    public var xpPerAchievement: Int
    /// Coins paid once for each new level.
    public var coinsPerLevel: Int
    /// XP to go from level 1 to 2; later levels grow as `base · level^exponent`.
    public var baseLevelXP: Double
    public var levelExponent: Double
    public var maxLevel: Int

    public init(xpPerKilometre: Int = 100, dailyXPCapMeters: Int = 25_000, xpPerZone: Int = 50, xpPerRelic: Int = 75,
                xpPerAchievement: Int = 100, coinsPerLevel: Int = 25, baseLevelXP: Double = 100,
                levelExponent: Double = 1.5, maxLevel: Int = 100) {
        self.xpPerKilometre = xpPerKilometre
        self.dailyXPCapMeters = dailyXPCapMeters
        self.xpPerZone = xpPerZone
        self.xpPerRelic = xpPerRelic
        self.xpPerAchievement = xpPerAchievement
        self.coinsPerLevel = coinsPerLevel
        self.baseLevelXP = baseLevelXP
        self.levelExponent = levelExponent
        self.maxLevel = maxLevel
    }

    public static let standard = ExplorerRules()
}

/// Lifetime XP, worked out from permanent facts rather than counted up as
/// events happen. Recomputing it after any HealthKit refresh gives the same
/// answer, and it can only grow.
public struct ExplorerXP: Hashable, Sendable {
    public let walking: Int
    public let zones: Int
    public let relics: Int
    public let achievements: Int
    public let rewards: Int

    public var total: Int { walking + zones + relics + achievements + rewards }

    public init(progression: ProgressionState, ledger: RewardLedger,
                achievements catalog: [Achievement] = AchievementCatalog.standard, rules: ExplorerRules = .standard) {
        let cappedMeters = progression.dailyBestMeters.values.reduce(0) { $0 + min(max(0, $1), rules.dailyXPCapMeters) }
        walking = cappedMeters * rules.xpPerKilometre / 1_000
        zones = progression.discoveredZoneIDs.count * rules.xpPerZone
        relics = progression.collectedItemIDs.count * rules.xpPerRelic
        achievements = catalog.filter { $0.isUnlocked(by: progression) }.count * rules.xpPerAchievement
        rewards = ledger.rewardXP
    }
}

/// Where a total XP sits on the level curve.
public struct ExplorerLevel: Hashable, Sendable {
    public let level: Int
    public let totalXP: Int
    /// XP earned since reaching `level`.
    public let xpIntoLevel: Int
    /// XP needed from `level` to the next one, or nil at the max level.
    public let xpForNextLevel: Int?

    public init(totalXP: Int, rules: ExplorerRules = .standard) {
        self.totalXP = max(0, totalXP)
        var level = 1
        var remaining = self.totalXP
        while level < rules.maxLevel {
            let step = Self.xpToAdvance(from: level, rules: rules)
            guard remaining >= step else { break }
            remaining -= step
            level += 1
        }
        self.level = level
        xpIntoLevel = remaining
        xpForNextLevel = level < rules.maxLevel ? Self.xpToAdvance(from: level, rules: rules) : nil
    }

    /// 0...1 toward the next level (1 at the max level).
    public var fraction: Double {
        guard let next = xpForNextLevel, next > 0 else { return 1 }
        return min(1, Double(xpIntoLevel) / Double(next))
    }

    /// XP to go from `level` to `level + 1`, rounded to a tidy multiple of 10.
    public static func xpToAdvance(from level: Int, rules: ExplorerRules = .standard) -> Int {
        let raw = rules.baseLevelXP * pow(Double(max(1, level)), rules.levelExponent)
        return max(10, Int((raw / 10).rounded()) * 10)
    }

    /// Total XP needed to reach `level` from zero.
    public static func totalXP(toReach level: Int, rules: ExplorerRules = .standard) -> Int {
        guard level > 1 else { return 0 }
        return (1..<min(level, rules.maxLevel)).reduce(0) { $0 + xpToAdvance(from: $1, rules: rules) }
    }
}

extension JournalEvents {
    public static func levelUp(to level: Int, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "level-\(level)", kind: .level, day: day, title: "Explorer Level \(level)",
                     detail: "Every step you take adds to your lifetime adventure.", iconID: "medal")
    }
}
