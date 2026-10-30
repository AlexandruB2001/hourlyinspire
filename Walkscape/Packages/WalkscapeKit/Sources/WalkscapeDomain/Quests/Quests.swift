import Foundation

// MARK: - Definitions

/// What a quest asks for. Every goal is measured from data the game already
/// keeps, so progress is the same however often it is recalculated.
public enum QuestGoal: Hashable, Sendable {
    case stepsToday(Int)
    case metersToday(Int)
    case chestsOpenedToday(Int)
    case coinsEarnedToday(Int)
    /// First-ever discoveries recorded in the Journal today.
    case newZonesToday(Int)
    /// You and at least one friend both walked today.
    case walkWithFriendToday
    case metersThisWeek(Int)
    case activeDaysThisWeek(count: Int, minimumMeters: Int)
    case chestsFoundThisWeek(Int)
    case newZonesThisWeek(Int)
    case expeditionCompletedThisWeek
    case teamMetersThisWeek(Int)
    /// The companion reaches its next growth stage this week.
    case companionGrowsThisWeek

    public var target: Int {
        switch self {
        case .stepsToday(let n), .metersToday(let n), .chestsOpenedToday(let n), .coinsEarnedToday(let n),
             .newZonesToday(let n), .metersThisWeek(let n), .chestsFoundThisWeek(let n), .newZonesThisWeek(let n),
             .teamMetersThisWeek(let n):
            return max(1, n)
        case .activeDaysThisWeek(let count, _): return max(1, count)
        case .walkWithFriendToday, .expeditionCompletedThisWeek, .companionGrowsThisWeek: return 1
        }
    }
}

public struct QuestDefinition: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case daily, weekly, companion
    }

    /// When a quest can be offered.
    public enum Requirement: Hashable, Sendable {
        case none, hasFriends, inTeam, hasCompanion, zonesLeftToDiscover(Int)
        /// In a team whose current expedition is at most this far from done.
        case expeditionWithin(meters: Int)
        /// The companion is at most this many km from its next stage.
        case companionStageWithin(kilometres: Int)
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let goal: QuestGoal
    public let coins: Int
    public let xp: Int
    public let requirement: Requirement

    public init(id: String, kind: Kind, title: String, goal: QuestGoal, coins: Int, xp: Int, requirement: Requirement = .none) {
        self.id = id
        self.kind = kind
        self.title = title
        self.goal = goal
        self.coins = coins
        self.xp = xp
        self.requirement = requirement
    }
}

/// The quest pools. Goals stay well inside an ordinary walk: nothing daily
/// asks for more than 3 km, nothing weekly for more than 15 km.
public enum QuestCatalog {
    public static let daily: [QuestDefinition] = [
        QuestDefinition(id: "steps-2000", kind: .daily, title: "Walk 2,000 steps", goal: .stepsToday(2_000), coins: 10, xp: 40),
        QuestDefinition(id: "steps-5000", kind: .daily, title: "Walk 5,000 steps", goal: .stepsToday(5_000), coins: 20, xp: 60),
        QuestDefinition(id: "walk-1km", kind: .daily, title: "Walk 1 kilometre", goal: .metersToday(1_000), coins: 10, xp: 40),
        QuestDefinition(id: "walk-3km", kind: .daily, title: "Walk 3 kilometres", goal: .metersToday(3_000), coins: 20, xp: 60),
        QuestDefinition(id: "open-chest", kind: .daily, title: "Open a trail chest", goal: .chestsOpenedToday(1), coins: 10, xp: 40),
        QuestDefinition(id: "earn-30", kind: .daily, title: "Earn 30 coins", goal: .coinsEarnedToday(30), coins: 10, xp: 40),
        QuestDefinition(id: "new-zone", kind: .daily, title: "Discover a new zone", goal: .newZonesToday(1), coins: 20, xp: 60,
                        requirement: .zonesLeftToDiscover(1)),
        QuestDefinition(id: "friend-walk", kind: .daily, title: "Walk on the same day as a friend", goal: .walkWithFriendToday,
                        coins: 15, xp: 50, requirement: .hasFriends),
    ]

    public static let weekly: [QuestDefinition] = [
        QuestDefinition(id: "week-15km", kind: .weekly, title: "Walk 15 km this week", goal: .metersThisWeek(15_000), coins: 40, xp: 150),
        QuestDefinition(id: "week-8km", kind: .weekly, title: "Walk 8 km this week", goal: .metersThisWeek(8_000), coins: 30, xp: 120),
        QuestDefinition(id: "week-5days", kind: .weekly, title: "Walk 1 km on 5 different days",
                        goal: .activeDaysThisWeek(count: 5, minimumMeters: 1_000), coins: 40, xp: 150),
        QuestDefinition(id: "week-3days", kind: .weekly, title: "Walk 1 km on 3 different days",
                        goal: .activeDaysThisWeek(count: 3, minimumMeters: 1_000), coins: 30, xp: 120),
        QuestDefinition(id: "week-chests", kind: .weekly, title: "Find 5 trail chests", goal: .chestsFoundThisWeek(5), coins: 30, xp: 120),
        QuestDefinition(id: "week-zones", kind: .weekly, title: "Discover 3 new zones", goal: .newZonesThisWeek(3), coins: 40, xp: 150,
                        requirement: .zonesLeftToDiscover(3)),
        QuestDefinition(id: "week-team", kind: .weekly, title: "Walk 25 km together with your team", goal: .teamMetersThisWeek(25_000),
                        coins: 40, xp: 150, requirement: .inTeam),
        QuestDefinition(id: "week-expedition", kind: .weekly, title: "Complete a team expedition", goal: .expeditionCompletedThisWeek,
                        coins: 50, xp: 200, requirement: .expeditionWithin(meters: 30_000)),
    ]

    public static let companion: [QuestDefinition] = [
        QuestDefinition(id: "companion-5km", kind: .companion, title: "Walk 5 km with your companion this week",
                        goal: .metersThisWeek(5_000), coins: 30, xp: 100, requirement: .hasCompanion),
        QuestDefinition(id: "companion-zones", kind: .companion, title: "Discover 2 new zones together",
                        goal: .newZonesThisWeek(2), coins: 30, xp: 100, requirement: .zonesLeftToDiscover(2)),
        QuestDefinition(id: "companion-grow", kind: .companion, title: "Help your companion reach its next stage",
                        goal: .companionGrowsThisWeek, coins: 40, xp: 150, requirement: .companionStageWithin(kilometres: 8)),
    ]

    public static let dailyCount = 3
    public static let weeklyCount = 3

    /// Paid once every weekly quest of a week is claimed.
    public static func weeklyChest(week: LocalDay) -> Reward {
        Reward(id: "quest-week-chest-\(week.isoString)", coins: 100, xp: 250)
    }

    public static func definition(withID id: String) -> QuestDefinition? {
        (daily + weekly + companion).first { $0.id == id }
    }
}

// MARK: - Picking the board

/// What the planner knows when it picks quests (once per day / week).
public struct QuestContext: Hashable, Sendable {
    public var hasFriends: Bool
    public var inTeam: Bool
    public var hasCompanion: Bool
    public var zonesLeftToDiscover: Int
    public var metersLeftInExpedition: Int?
    public var companionKilometresToNextStage: Int?

    public init(hasFriends: Bool = false, inTeam: Bool = false, hasCompanion: Bool = false, zonesLeftToDiscover: Int = 0,
                metersLeftInExpedition: Int? = nil, companionKilometresToNextStage: Int? = nil) {
        self.hasFriends = hasFriends
        self.inTeam = inTeam
        self.hasCompanion = hasCompanion
        self.zonesLeftToDiscover = zonesLeftToDiscover
        self.metersLeftInExpedition = metersLeftInExpedition
        self.companionKilometresToNextStage = companionKilometresToNextStage
    }

    func allows(_ requirement: QuestDefinition.Requirement) -> Bool {
        switch requirement {
        case .none: return true
        case .hasFriends: return hasFriends
        case .inTeam: return inTeam
        case .hasCompanion: return hasCompanion
        case .zonesLeftToDiscover(let n): return zonesLeftToDiscover >= n
        case .expeditionWithin(let meters): return inTeam && (metersLeftInExpedition.map { $0 <= meters } ?? false)
        case .companionStageWithin(let km): return hasCompanion && (companionKilometresToNextStage.map { $0 <= km } ?? false)
        }
    }
}

public enum QuestPlanner {
    /// Picks `count` quests from `pool`, deterministically for `seed`, never
    /// two with the same goal type (no "walk 1 km" and "walk 3 km" together).
    public static func pick(_ count: Int, from pool: [QuestDefinition], seed: String, context: QuestContext) -> [String] {
        let eligible = pool.filter { context.allows($0.requirement) }
        let shuffled = eligible.sorted { stableHash("\(seed)#\($0.id)") < stableHash("\(seed)#\($1.id)") }
        var picked: [QuestDefinition] = []
        for quest in shuffled where picked.count < count {
            if !picked.contains(where: { sameFamily($0.goal, quest.goal) }) { picked.append(quest) }
        }
        return picked.map(\.id)
    }

    public static func daily(for day: LocalDay, context: QuestContext) -> [String] {
        pick(QuestCatalog.dailyCount, from: QuestCatalog.daily, seed: "daily-\(day.isoString)", context: context)
    }

    public static func weekly(for week: LocalDay, context: QuestContext) -> [String] {
        pick(QuestCatalog.weeklyCount, from: QuestCatalog.weekly, seed: "weekly-\(week.isoString)", context: context)
    }

    public static func companion(for week: LocalDay, context: QuestContext) -> [String] {
        guard context.hasCompanion else { return [] }
        return pick(1, from: QuestCatalog.companion, seed: "companion-\(week.isoString)", context: context)
    }

    static func sameFamily(_ a: QuestGoal, _ b: QuestGoal) -> Bool {
        switch (a, b) {
        case (.stepsToday, .stepsToday), (.metersToday, .metersToday), (.metersThisWeek, .metersThisWeek),
             (.activeDaysThisWeek, .activeDaysThisWeek), (.newZonesThisWeek, .newZonesThisWeek):
            return true
        default:
            return false
        }
    }

    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return hash
    }
}

// MARK: - Tracking

/// The few counters quests need that the rest of the game doesn't keep, plus
/// the boards chosen for the current day and week (stored, so they never
/// change mid-day, even if you add a friend or join a team).
public struct QuestTracker: Codable, Hashable, Sendable {
    public private(set) var day: LocalDay?
    public private(set) var dailyQuestIDs: [String]
    public private(set) var chestsOpenedToday: Int
    /// Wallet lifetime coins at the start of the day; today's earnings are the difference.
    public private(set) var lifetimeCoinsAtDayStart: Int

    public private(set) var week: LocalDay?
    public private(set) var weeklyQuestIDs: [String]
    public private(set) var companionQuestIDs: [String]
    /// Trail chests found per day this week (ISO date → count).
    public private(set) var chestsFoundByDay: [String: Int]
    /// Companion stage when the week began.
    public private(set) var companionStageAtWeekStart: Int?

    public init() {
        day = nil
        dailyQuestIDs = []
        chestsOpenedToday = 0
        lifetimeCoinsAtDayStart = 0
        week = nil
        weeklyQuestIDs = []
        companionQuestIDs = []
        chestsFoundByDay = [:]
        companionStageAtWeekStart = nil
    }

    /// Starts a new day or week when needed (local midnight, Monday midnight)
    /// and picks its quests. Earlier claims live in the ledger, so nothing
    /// earned is affected by a reset.
    public mutating func roll(to today: LocalDay, context: QuestContext, wallet: WalletState, companionStage: Int?) {
        if day != today {
            day = today
            dailyQuestIDs = QuestPlanner.daily(for: today, context: context)
            chestsOpenedToday = 0
            lifetimeCoinsAtDayStart = wallet.lifetimeCoins
        }
        let thisWeek = TeamWeek.start(of: today)
        if week != thisWeek {
            week = thisWeek
            weeklyQuestIDs = QuestPlanner.weekly(for: thisWeek, context: context)
            companionQuestIDs = QuestPlanner.companion(for: thisWeek, context: context)
            chestsFoundByDay = [:]
            companionStageAtWeekStart = companionStage
        }
    }

    public mutating func recordChestOpened() { chestsOpenedToday += 1 }

    public mutating func recordChestsFound(_ count: Int, on day: LocalDay) {
        guard let week, day >= week, day < week.adding(days: 7) else { return }
        chestsFoundByDay[day.isoString] = max(chestsFoundByDay[day.isoString] ?? 0, count)
    }

    public var chestsFoundThisWeek: Int { chestsFoundByDay.values.reduce(0, +) }
}

/// Everything needed to measure quest progress at one moment.
public struct QuestFacts: Hashable, Sendable {
    public var today: LocalDay
    public var stepsToday: Int
    public var metersToday: Int
    public var chestsOpenedToday: Int
    public var coinsEarnedToday: Int
    public var newZonesToday: Int
    public var friendWalkedToday: Bool
    public var metersThisWeek: Int
    /// Best distance on each day of this week, Monday first.
    public var weekDailyMeters: [Int]
    public var chestsFoundThisWeek: Int
    public var newZonesThisWeek: Int
    public var expeditionsThisWeek: Int
    public var teamMetersThisWeek: Int
    public var companionGrewThisWeek: Bool

    public func activeDaysThisWeek(minimumMeters: Int) -> Int {
        weekDailyMeters.filter { $0 >= minimumMeters }.count
    }

    /// Builds facts from the game state. `todaySteps`/`todayMeters` are the
    /// latest totals; weekly distance comes from the best distance per day.
    public static func make(today: LocalDay, steps: Int, meters: Int, progression: ProgressionState, wallet: WalletState,
                            journal: JourneyJournal, tracker: QuestTracker, friendWalkedToday: Bool, teamMetersThisWeek: Int,
                            companionStage: Int?) -> QuestFacts {
        let week = TeamWeek.start(of: today)
        let weekDays = (0..<7).map { week.adding(days: $0).isoString }
        let weekBest = weekDays.map { progression.dailyBestMeters[$0] ?? 0 }
        let inWeek: (JournalEntry) -> Bool = { $0.day >= week && $0.day <= today }
        return QuestFacts(
            today: today,
            stepsToday: max(0, steps),
            metersToday: max(0, meters),
            chestsOpenedToday: tracker.day == today ? tracker.chestsOpenedToday : 0,
            coinsEarnedToday: tracker.day == today ? max(0, wallet.lifetimeCoins - tracker.lifetimeCoinsAtDayStart) : 0,
            newZonesToday: journal.entries.filter { $0.kind == .zone && $0.day == today }.count,
            friendWalkedToday: friendWalkedToday && meters > 0,
            metersThisWeek: weekBest.reduce(0, +),
            weekDailyMeters: weekBest,
            chestsFoundThisWeek: tracker.week == week ? tracker.chestsFoundThisWeek : 0,
            newZonesThisWeek: journal.entries.filter { $0.kind == .zone && inWeek($0) }.count,
            expeditionsThisWeek: journal.entries.filter { $0.kind == .expedition && inWeek($0) }.count,
            teamMetersThisWeek: max(0, teamMetersThisWeek),
            companionGrewThisWeek: {
                guard let now = companionStage, let start = tracker.companionStageAtWeekStart, tracker.week == week else { return false }
                return now > start
            }())
    }

    public func progress(of goal: QuestGoal) -> Int {
        let value: Int
        switch goal {
        case .stepsToday: value = stepsToday
        case .metersToday: value = metersToday
        case .chestsOpenedToday: value = chestsOpenedToday
        case .coinsEarnedToday: value = coinsEarnedToday
        case .newZonesToday: value = newZonesToday
        case .walkWithFriendToday: value = friendWalkedToday ? 1 : 0
        case .metersThisWeek: value = metersThisWeek
        case .activeDaysThisWeek(_, let minimum): value = activeDaysThisWeek(minimumMeters: minimum)
        case .chestsFoundThisWeek: value = chestsFoundThisWeek
        case .newZonesThisWeek: value = newZonesThisWeek
        case .expeditionCompletedThisWeek: value = expeditionsThisWeek
        case .teamMetersThisWeek: value = teamMetersThisWeek
        case .companionGrowsThisWeek: value = companionGrewThisWeek ? 1 : 0
        }
        return min(goal.target, max(0, value))
    }
}

extension JournalEvents {
    public static func weeklyChest(week: LocalDay, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "quest-week-chest-\(week.isoString)", kind: .quest, day: day, title: "Weekly quests complete",
                     detail: "Every weekly quest done. The weekly chest is yours!", iconID: "chest")
    }
}

// MARK: - The board

/// One quest as shown to the player.
public struct QuestStatus: Identifiable, Hashable, Sendable {
    public let quest: QuestDefinition
    /// The reward id: includes the day or week, so each occurrence pays once.
    public let rewardID: String
    public let progress: Int
    public let isClaimed: Bool

    public var id: String { rewardID }
    public var isComplete: Bool { progress >= quest.goal.target }
    public var isClaimable: Bool { isComplete && !isClaimed }
    public var fraction: Double { Double(progress) / Double(quest.goal.target) }
    public var reward: Reward { Reward(id: rewardID, coins: quest.coins, xp: quest.xp) }
}

public struct QuestBoard: Hashable, Sendable {
    public let day: LocalDay
    public let week: LocalDay
    public let daily: [QuestStatus]
    public let weekly: [QuestStatus]
    public let companion: [QuestStatus]

    public init(tracker: QuestTracker, facts: QuestFacts, ledger: RewardLedger) {
        day = tracker.day ?? facts.today
        week = tracker.week ?? TeamWeek.start(of: facts.today)
        func status(_ id: String, period: String) -> QuestStatus? {
            guard let quest = QuestCatalog.definition(withID: id) else { return nil }
            let rewardID = "quest-\(quest.kind.rawValue)-\(period)-\(quest.id)"
            return QuestStatus(quest: quest, rewardID: rewardID, progress: facts.progress(of: quest.goal),
                               isClaimed: ledger.hasClaimed(rewardID))
        }
        daily = tracker.dailyQuestIDs.compactMap { status($0, period: day.isoString) }
        weekly = tracker.weeklyQuestIDs.compactMap { status($0, period: week.isoString) }
        companion = tracker.companionQuestIDs.compactMap { status($0, period: week.isoString) }
        weeklyChest = QuestCatalog.weeklyChest(week: week)
        weeklyChestClaimed = ledger.hasClaimed(weeklyChest.id)
    }

    public let weeklyChest: Reward
    public let weeklyChestClaimed: Bool

    /// The weekly chest opens once every weekly quest is claimed.
    public var weeklyChestReady: Bool {
        !weekly.isEmpty && weekly.allSatisfy(\.isClaimed) && !weeklyChestClaimed
    }

    public var claimableCount: Int {
        (daily + weekly + companion).filter(\.isClaimable).count + (weeklyChestReady ? 1 : 0)
    }
}
