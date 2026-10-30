import Foundation

/// What creating things costs. The server charges these (charge_coins in the
/// groups migration); the app shows them and checks the balance first.
public enum CreationCosts {
    public static let group = 500
    public static let team = 25

    /// The wallet key a charge is recorded under. Matches the server, which
    /// writes the same key into the cloud save, so the charge counts once.
    public static func chargeKey(_ kind: Kind, requestID: UUID) -> String {
        "\(kind.rawValue)-\(requestID.uuidString.lowercased())"
    }

    public enum Kind: String, Sendable {
        case group, team
    }
}

/// The three views of the Social tab's dropdown, in menu order. The raw
/// value is shown and remembered between launches.
public enum SocialSection: String, CaseIterable, Identifiable, Sendable {
    case friends = "Friends"
    case teams = "Teams"
    case groups = "Groups"

    public var id: String { rawValue }

    /// Item sprite shown next to the name.
    public var spriteID: String {
        switch self {
        case .friends: return "boot"
        case .teams: return "team-badge"
        case .groups: return "flag"
        }
    }
}

/// Rules for community groups, mirrored by the database.
public enum GroupRules {
    public static let maxGroups = 5
    public static let codeLength = 6
    /// No 0/O or 1/I, so codes are easy to read aloud and type.
    public static let codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    public static let nameLength = 3...40
    public static let descriptionLimit = 160
    public static let topCount = 10
    public static let pageSize = 25

    /// Emblems a group can pick, from the game's item sprites.
    public static let emblems = ["team-badge", "boot", "compass", "star", "medal", "flag", "crystal", "lantern",
                                 "clover", "feather", "maple", "mushroom", "shell", "snowflake", "cherry", "pinecone"]

    /// Prefix of the text in a group's QR code.
    public static let qrPrefix = "walkscape://group/"

    public static func qrPayload(code: String) -> String { qrPrefix + code }

    /// A valid code from typed text or a scanned QR code (any case, spaces and
    /// dashes ignored), or nil.
    public static func code(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix(qrPrefix) { text = String(text.dropFirst(qrPrefix.count)) }
        let code = text.uppercased().filter { !" -".contains($0) }
        guard code.count == codeLength, code.allSatisfy({ codeAlphabet.contains($0) }) else { return nil }
        return code
    }

    /// The name as the server will store it, or nil if it would be rejected.
    public static func cleanName(_ raw: String) -> String? {
        let clean = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard nameLength.contains(clean.count), let first = clean.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " &.,'!()_-"))
        return clean.unicodeScalars.allSatisfy(allowed.contains) ? clean : nil
    }

    public static func isValidDescription(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).count <= descriptionLimit
    }
}

/// A group the player belongs to.
public struct CommunityGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let emblem: String
    public let joinCode: String
    public let memberCount: Int
    public let isOwner: Bool

    public init(id: String, name: String, description: String, emblem: String, joinCode: String, memberCount: Int,
                isOwner: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.emblem = emblem
        self.joinCode = joinCode
        self.memberCount = memberCount
        self.isOwner = isOwner
    }
}

/// What a code leads to, shown before joining.
public struct GroupPreview: Identifiable, Hashable, Sendable {
    public let id: String
    public let code: String
    public let name: String
    public let description: String
    public let emblem: String
    public let memberCount: Int
    public let isMember: Bool

    public init(id: String, code: String, name: String, description: String, emblem: String, memberCount: Int,
                isMember: Bool) {
        self.id = id
        self.code = code
        self.name = name
        self.description = description
        self.emblem = emblem
        self.memberCount = memberCount
        self.isMember = isMember
    }
}

public enum LeaderboardPeriod: String, CaseIterable, Identifiable, Sendable {
    case day, week

    public var id: String { rawValue }
    public var title: String { self == .day ? "Today" : "This week" }

    /// First calendar day counted for `day`: the day itself, or the Monday of
    /// its week (the same weeks as quests and teams).
    public func firstDay(for day: LocalDay) -> LocalDay {
        switch self {
        case .day: return day
        case .week: return TeamWeek.start(of: day)
        }
    }
}

/// One member's row on a group leaderboard.
public struct GroupStanding: Identifiable, Hashable, Sendable {
    public let userID: UserID
    public let username: String
    public let avatarID: String
    public let rank: Int
    /// Nil when the member doesn't share their progress.
    public let steps: Int?
    public let meters: Int?
    public let estimated: Bool
    public let updatedAt: Date?
    public let isMe: Bool

    public var id: UserID { userID }
    public var isSharing: Bool { meters != nil }

    public init(userID: UserID, username: String, avatarID: String, rank: Int, steps: Int?, meters: Int?,
                estimated: Bool, updatedAt: Date?, isMe: Bool) {
        self.userID = userID
        self.username = username
        self.avatarID = avatarID
        self.rank = rank
        self.steps = steps
        self.meters = meters
        self.estimated = estimated
        self.updatedAt = updatedAt
        self.isMe = isMe
    }
}

/// A page of a leaderboard. The server always adds the player's own row, so
/// `me` is known even when they rank outside the page.
public struct GroupLeaderboardPage: Hashable, Sendable {
    public let period: LeaderboardPeriod
    public let rows: [GroupStanding]
    public let memberCount: Int
    public let me: GroupStanding?

    /// `rows` as the server sends them: the page, plus the player's own row
    /// when they rank outside it (making one more than `limit`).
    public init(period: LeaderboardPeriod, rows: [GroupStanding], memberCount: Int, limit: Int) {
        self.period = period
        me = rows.first(where: \.isMe)
        self.rows = rows.count > limit ? rows.filter { !$0.isMe } : rows
        self.memberCount = memberCount
    }

    /// Whether the player's own row is outside this page (shown pinned below it).
    public var meIsElsewhere: Bool { me.map { mine in !rows.contains(mine) } ?? false }

    /// The most recent update shown on this page.
    public var lastUpdated: Date? { rows.compactMap(\.updatedAt).max() }
}

public struct GroupMember: Identifiable, Hashable, Sendable {
    public let userID: UserID
    public let username: String
    public let avatarID: String
    public let isOwner: Bool
    public let joinedAt: Date?

    public var id: UserID { userID }

    public init(userID: UserID, username: String, avatarID: String, isOwner: Bool, joinedAt: Date?) {
        self.userID = userID
        self.username = username
        self.avatarID = avatarID
        self.isOwner = isOwner
        self.joinedAt = joinedAt
    }
}

public enum GroupError: Error, Hashable, Sendable {
    case notSignedIn
    case notFound
    case limitReached
    case groupFull
    case insufficientCoins
    case invalidName
    case invalidDescription
    case notOwner
    /// The player has no cloud save to pay from yet (sync first).
    case needsCloudSave
    /// The cloud save is from an older app version.
    case updateApp
    case network(String)

    /// What to tell the player.
    public var message: String {
        switch self {
        case .notSignedIn: return "Sign in to use groups."
        case .notFound: return "No group has that code. Check it and try again."
        case .limitReached: return "You're in \(GroupRules.maxGroups) groups already. Leave one first."
        case .groupFull: return "That group is full."
        case .insufficientCoins: return "You don't have enough coins yet. Walk a little more!"
        case .invalidName:
            return "Group names need \(GroupRules.nameLength.lowerBound)–\(GroupRules.nameLength.upperBound) letters, numbers or spaces."
        case .invalidDescription: return "Descriptions can be up to \(GroupRules.descriptionLimit) characters."
        case .notOwner: return "Only the group's owner can do that."
        case .needsCloudSave: return "Your progress hasn't reached the server yet. Try again in a moment."
        case .updateApp: return "Update Walkscape to do that."
        case .network(let message): return message.isEmpty ? "That didn't go through." : message
        }
    }
}

public protocol GroupRepository: Sendable {
    func myGroups() async throws -> [CommunityGroup]
    func createGroup(requestID: UUID, name: String, description: String, emblem: String) async throws -> String
    func preview(code: String) async throws -> GroupPreview?
    func join(code: String) async throws -> String
    func leave(groupID: String) async throws
    func remove(member: UserID, from groupID: String) async throws
    func update(groupID: String, name: String, description: String, emblem: String) async throws
    func regenerateCode(groupID: String) async throws -> String
    func members(groupID: String, limit: Int, offset: Int) async throws -> (members: [GroupMember], total: Int)
    func leaderboard(groupID: String, period: LeaderboardPeriod, day: LocalDay, limit: Int, offset: Int) async throws
        -> GroupLeaderboardPage
}
