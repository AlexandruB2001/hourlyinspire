import Foundation

/// One line on the Daily Leaderboard.
public struct DailyLeaderboardRow: Identifiable, Hashable, Sendable {
    public let userID: UserID
    public let username: String
    public let avatarID: String
    public let outfit: [String]
    /// Nil when this day isn't ranked (no walk yet, estimated or under review).
    public let rank: Int?
    public let meters: Int
    public let isMe: Bool

    public var id: UserID { userID }

    public init(userID: UserID, username: String, avatarID: String, outfit: [String], rank: Int?, meters: Int, isMe: Bool) {
        self.userID = userID
        self.username = username
        self.avatarID = avatarID
        self.outfit = outfit
        self.rank = rank
        self.meters = meters
        self.isMe = isMe
    }
}

/// Everyone's walking for one calendar day: the top walkers and your position.
public struct DailyLeaderboard: Hashable, Sendable {
    /// How many walkers the board shows. Raise it as the game grows.
    public static let topCount = 3

    public let top: [DailyLeaderboardRow]
    public let me: DailyLeaderboardRow?
    /// Ranked players today.
    public let players: Int
    public let isUnderReview: Bool
    public var isShownToOthers: Bool

    public init(rows: [DailyLeaderboardRow], players: Int, isUnderReview: Bool, isShownToOthers: Bool) {
        top = Array(rows.filter { $0.rank != nil }.prefix(Self.topCount))
        me = rows.first(where: \.isMe)
        self.players = players
        self.isUnderReview = isUnderReview
        self.isShownToOthers = isShownToOthers
    }

    /// What to say on your own line.
    public var myStatus: DailyLeaderboardStatus {
        guard let me else { return .notWalked }
        if let rank = me.rank { return .ranked(rank: rank, of: players) }
        if isUnderReview { return .underReview }
        return me.meters > 0 ? .estimated : .notWalked
    }
}

public enum DailyLeaderboardStatus: Hashable, Sendable {
    case ranked(rank: Int, of: Int)
    case notWalked
    case estimated
    case underReview
}
