import Foundation

/// The caller's walking team.
public struct Team: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Short code others type (or receive in an invite) to join.
    public let joinCode: String
    public let memberCount: Int
    public let isOwner: Bool
    public let createdOn: LocalDay?
    /// Distance all sharing members have walked since joining, in metres.
    public let totalMeters: Int

    public init(id: String, name: String, joinCode: String, memberCount: Int, isOwner: Bool,
                createdOn: LocalDay?, totalMeters: Int) {
        self.id = id
        self.name = name
        self.joinCode = joinCode
        self.memberCount = memberCount
        self.isOwner = isOwner
        self.createdOn = createdOn
        self.totalMeters = totalMeters
    }
}

/// One member's walking for a day and for the current week. Totals are nil
/// when the member has sharing turned off or hasn't synced.
public struct TeamMember: Identifiable, Hashable, Sendable {
    public let id: UserID
    public let username: String
    public let avatarID: String
    public let isCurrentUser: Bool
    public let isOwner: Bool
    public let daySteps: Int?
    public let dayMeters: Int?
    public let weekMeters: Int?
    public let updatedAt: Date?

    public init(id: UserID, username: String, avatarID: String, isCurrentUser: Bool, isOwner: Bool,
                daySteps: Int?, dayMeters: Int?, weekMeters: Int?, updatedAt: Date?) {
        self.id = id
        self.username = username
        self.avatarID = avatarID
        self.isCurrentUser = isCurrentUser
        self.isOwner = isOwner
        self.daySteps = daySteps
        self.dayMeters = dayMeters
        self.weekMeters = weekMeters
        self.updatedAt = updatedAt
    }

    public var isSharing: Bool { dayMeters != nil || weekMeters != nil }
}

/// A team's place in this week's competition.
public struct TeamStanding: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let memberCount: Int
    public let weekMeters: Int
    public let rank: Int
    public let isMine: Bool

    public init(id: String, name: String, memberCount: Int, weekMeters: Int, rank: Int, isMine: Bool) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
        self.weekMeters = weekMeters
        self.rank = rank
        self.isMine = isMine
    }
}

public struct TeamInvite: Identifiable, Hashable, Sendable {
    public let id: String
    public let teamName: String
    public let fromUsername: String

    public init(id: String, teamName: String, fromUsername: String) {
        self.id = id
        self.teamName = teamName
        self.fromUsername = fromUsername
    }
}

/// Everything the Team screen shows.
public struct TeamDashboard: Hashable, Sendable {
    public let team: Team
    public let members: [TeamMember]
    public let standings: [TeamStanding]
    public let weekStart: LocalDay

    public init(team: Team, members: [TeamMember], standings: [TeamStanding], weekStart: LocalDay) {
        self.team = team
        self.members = members
        self.standings = standings
        self.weekStart = weekStart
    }

    /// Combined distance of sharing members today.
    public var dayMeters: Int { members.compactMap(\.dayMeters).reduce(0, +) }
    public var weekMeters: Int { members.compactMap(\.weekMeters).reduce(0, +) }
    public var myStanding: TeamStanding? { standings.first(where: \.isMine) }

    /// Members ordered by today's distance (non-sharing members last).
    public var membersByToday: [TeamMember] {
        members.sorted { ($0.dayMeters ?? -1, $1.username) > ($1.dayMeters ?? -1, $0.username) }
    }

    public var expeditions: ExpeditionProgress { ExpeditionProgress(totalMeters: team.totalMeters) }
    public var badges: [TeamBadge] { TeamBadge.earned(weekMeters: weekMeters, expeditions: expeditions) }
}

// MARK: - Expeditions

/// A shared distance goal the whole team walks toward, one after another.
public struct Expedition: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let goalMeters: Int
    public let spriteID: String
}

public enum ExpeditionCatalog {
    public static let all: [Expedition] = [
        Expedition(id: "meadow-ramble", name: "Meadow Ramble", detail: "A gentle warm-up for the whole team.",
                   goalMeters: 25_000, spriteID: "clover"),
        Expedition(id: "summit-relay", name: "Summit Relay", detail: "Carry the flag to the top together.",
                   goalMeters: 75_000, spriteID: "flag"),
        Expedition(id: "coast-to-coast", name: "Coast to Coast", detail: "From the Meadow all the way to the sea.",
                   goalMeters: 150_000, spriteID: "spyglass"),
        Expedition(id: "starlight-trek", name: "Starlight Trek", detail: "Follow the aurora far past the map.",
                   goalMeters: 300_000, spriteID: "starfall"),
        Expedition(id: "grand-tour", name: "The Grand Tour", detail: "A legendary walk, one step at a time.",
                   goalMeters: 600_000, spriteID: "medal"),
    ]
}

/// Where a team's cumulative distance sits on the expedition list.
public struct ExpeditionProgress: Hashable, Sendable {
    public let totalMeters: Int
    public let completed: [Expedition]
    /// The expedition in progress, or nil once every one is done.
    public let current: Expedition?

    public init(totalMeters: Int, catalog: [Expedition] = ExpeditionCatalog.all) {
        self.totalMeters = max(0, totalMeters)
        var walked = self.totalMeters
        var done: [Expedition] = []
        var active: Expedition?
        for expedition in catalog {
            if walked >= expedition.goalMeters {
                done.append(expedition)
                walked -= expedition.goalMeters
            } else {
                active = expedition
                break
            }
        }
        completed = done
        current = active
        metersIntoCurrent = walked
    }

    /// Metres walked toward `current`.
    public let metersIntoCurrent: Int

    public var fraction: Double {
        guard let current else { return 1 }
        return Double(metersIntoCurrent) / Double(current.goalMeters)
    }
}

// MARK: - Badges

public struct TeamBadge: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let spriteID: String

    public static func earned(weekMeters: Int, expeditions: ExpeditionProgress) -> [TeamBadge] {
        var badges: [TeamBadge] = []
        for (meters, name, sprite) in [(25_000, "Busy Week", "boot"), (50_000, "Trail Squad", "compass"),
                                       (100_000, "Century Crew", "medal")] where weekMeters >= meters {
            badges.append(TeamBadge(id: "week-\(meters)", name: name,
                                    detail: "Walked \(DistanceFormatting.kilometres(meters)) together this week.",
                                    spriteID: sprite))
        }
        for expedition in expeditions.completed {
            badges.append(TeamBadge(id: "expedition-\(expedition.id)", name: expedition.name,
                                    detail: "Expedition complete.", spriteID: expedition.spriteID))
        }
        return badges
    }
}

// MARK: - Weeks

public enum TeamWeek {
    /// Competitions run Monday to Sunday in each walker's local dates.
    public static func start(of day: LocalDay) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        // Gregorian weekday: 1 = Sunday ... 7 = Saturday.
        let daysSinceMonday = (calendar.component(.weekday, from: date) + 5) % 7
        return day.adding(days: -daysSinceMonday)
    }
}

// MARK: - Repository

public enum TeamRepositoryError: Error, Hashable, Sendable {
    case notSignedIn
    case notConfigured
    case teamNotFound
    case alreadyInTeam
    case notInTeam
    case notFriends
    case invalidName
    case network(String)
}

public protocol TeamRepository: Sendable {
    /// Nil when the caller isn't in a team.
    func dashboard(for day: LocalDay, now: Date) async throws -> TeamDashboard?
    func invites() async throws -> [TeamInvite]
    func createTeam(named name: String) async throws
    func joinTeam(code: String) async throws
    func leaveTeam() async throws
    func invite(friend: UserID) async throws
    func respond(to invite: TeamInvite, accept: Bool) async throws
}
