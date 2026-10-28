import Foundation
import WalkscapeDomain

/// `TeamRepository` backed by the team database functions.
public struct SupabaseTeamRepository: TeamRepository {
    private let api: SupabaseAPI
    /// The signed-in user's id, to mark "you" in member lists.
    private let currentUserID: @Sendable () async -> UserID?

    public init(api: SupabaseAPI, currentUserID: @escaping @Sendable () async -> UserID?) {
        self.api = api
        self.currentUserID = currentUserID
    }

    struct TeamRow: Decodable {
        let id: String
        let name: String
        let joinCode: String
        let memberCount: Int
        let isOwner: Bool?
        let createdAt: Date?
        let totalMeters: Int

        enum CodingKeys: String, CodingKey {
            case id, name, joinCode = "join_code", memberCount = "member_count", isOwner = "is_owner"
            case createdAt = "created_at", totalMeters = "total_meters"
        }
    }

    struct MemberRow: Decodable {
        let userID: String
        let username: String
        let avatarID: String
        let isOwner: Bool?
        let daySteps: Int?
        let dayMeters: Int?
        let weekMeters: Int?
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id", username, avatarID = "avatar_id", isOwner = "is_owner", daySteps = "day_steps"
            case dayMeters = "day_meters", weekMeters = "week_meters", updatedAt = "updated_at"
        }
    }

    struct StandingRow: Decodable {
        let teamID: String
        let name: String
        let memberCount: Int
        let weekMeters: Int
        let rank: Int

        enum CodingKeys: String, CodingKey {
            case teamID = "team_id", name, memberCount = "member_count", weekMeters = "week_meters", rank
        }
    }

    struct InviteRow: Decodable {
        let id: String
        let teamName: String
        let fromUsername: String

        enum CodingKeys: String, CodingKey { case id, teamName = "team_name", fromUsername = "from_username" }
    }

    public func dashboard(for day: LocalDay, now: Date) async throws -> TeamDashboard? {
        let teams: [TeamRow] = try await run { try await api.call("my_team") }
        guard let row = teams.first else { return nil }
        let weekStart = TeamWeek.start(of: day)
        struct DayParams: Encodable { let p_local_date: String; let p_week_start: String }
        struct WeekParams: Encodable { let p_week_start: String }
        async let memberRows: [MemberRow] = run {
            try await api.call("team_member_days", DayParams(p_local_date: day.isoString, p_week_start: weekStart.isoString))
        }
        async let standingRows: [StandingRow] = run {
            try await api.call("team_week_standings", WeekParams(p_week_start: weekStart.isoString))
        }
        let me = await currentUserID()
        let (members, standings) = try await (memberRows, standingRows)
        let teamID = row.id.lowercased()
        let calendar = Calendar(identifier: .gregorian)
        let team = Team(id: teamID, name: row.name, joinCode: row.joinCode, memberCount: row.memberCount,
                        isOwner: row.isOwner ?? false,
                        createdOn: row.createdAt.map { LocalDay(date: $0, timeZone: calendar.timeZone) },
                        totalMeters: row.totalMeters)
        return TeamDashboard(
            team: team,
            members: members.map { member in
                let id = UserID(member.userID.lowercased())
                return TeamMember(id: id, username: member.username, avatarID: member.avatarID, isCurrentUser: id == me,
                                  isOwner: member.isOwner ?? false, daySteps: member.daySteps, dayMeters: member.dayMeters,
                                  weekMeters: member.weekMeters, updatedAt: member.updatedAt)
            },
            standings: standings.map {
                TeamStanding(id: $0.teamID.lowercased(), name: $0.name, memberCount: $0.memberCount,
                             weekMeters: $0.weekMeters, rank: $0.rank, isMine: $0.teamID.lowercased() == teamID)
            },
            weekStart: weekStart)
    }

    public func invites() async throws -> [TeamInvite] {
        let rows: [InviteRow] = try await run { try await api.call("my_team_invites") }
        return rows.map { TeamInvite(id: $0.id.lowercased(), teamName: $0.teamName, fromUsername: $0.fromUsername) }
    }

    public func createTeam(named name: String) async throws {
        struct Params: Encodable { let p_name: String }
        _ = try await run { try await api.call("create_team", Params(p_name: name)) as IgnoredResult }
    }

    public func joinTeam(code: String) async throws {
        struct Params: Encodable { let p_code: String }
        try await run { try await api.call("join_team", Params(p_code: code)) }
    }

    public func leaveTeam() async throws {
        try await run { try await api.call("leave_team") }
    }

    public func invite(friend: UserID) async throws {
        struct Params: Encodable { let p_friend_id: String }
        try await run { try await api.call("invite_friend_to_team", Params(p_friend_id: friend.rawValue)) }
    }

    public func respond(to invite: TeamInvite, accept: Bool) async throws {
        struct Params: Encodable { let p_invite_id: String; let p_accept: Bool }
        try await run { try await api.call("respond_to_team_invite", Params(p_invite_id: invite.id, p_accept: accept)) }
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as BackendError {
            throw Self.map(error)
        }
    }

    static func map(_ error: BackendError) -> TeamRepositoryError {
        switch error {
        case .notSignedIn: return .notSignedIn
        case .network(let message): return .network(message)
        case .server(_, _, let message):
            switch message {
            case "team_not_found", "invite_not_found": return .teamNotFound
            case "already_in_team": return .alreadyInTeam
            case "not_in_team": return .notInTeam
            case "not_friends": return .notFriends
            case "invalid_team_name": return .invalidName
            case "team_full": return .network("That team is full (12 walkers).")
            case "not_authenticated": return .notSignedIn
            default: return .network(message)
            }
        case .invalidResponse, .decoding: return .network("Unexpected response from the server")
        }
    }
}

/// `ReferralRepository` backed by the referral database functions.
public struct SupabaseReferralRepository: ReferralRepository {
    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    struct StatusRow: Decodable {
        let referralCode: String
        let hasRedeemed: Bool
        let canRedeem: Bool

        enum CodingKeys: String, CodingKey { case referralCode = "referral_code", hasRedeemed = "has_redeemed", canRedeem = "can_redeem" }
    }

    struct InviteeRow: Decodable {
        let id: String
        let username: String
        let qualified: Bool
        let progress: Double
    }

    struct ChestRow: Decodable {
        let id: String
        let rewardCoins: Int

        enum CodingKeys: String, CodingKey { case id, rewardCoins = "reward_coins" }
    }

    public func status() async throws -> ReferralStatus {
        async let statusRows: [StatusRow] = run { try await api.call("my_referral_status") }
        async let inviteeRows: [InviteeRow] = run { try await api.call("my_referral_invitees") }
        let (rows, invitees) = try await (statusRows, inviteeRows)
        guard let row = rows.first else { throw ReferralError.notSignedIn }
        return ReferralStatus(code: row.referralCode, hasRedeemedCode: row.hasRedeemed, canRedeemCode: row.canRedeem,
                              invitees: invitees.map {
                                  ReferralInvitee(id: $0.id.lowercased(), username: $0.username, qualified: $0.qualified,
                                                  progress: $0.progress)
                              })
    }

    public func redeem(code: String) async throws {
        struct Params: Encodable { let p_code: String }
        try await run { try await api.call("redeem_referral_code", Params(p_code: ReferralRules.normalize(code))) }
    }

    public func readyChests() async throws -> [ReferralChest] {
        let rows: [ChestRow] = try await run { try await api.call("ready_referral_chests") }
        return rows.map { ReferralChest(id: $0.id.lowercased(), coins: $0.rewardCoins) }
    }

    public func markOpened(_ chest: ReferralChest) async throws {
        struct Params: Encodable { let p_referral_id: String }
        try await run { try await api.call("mark_referral_chest_opened", Params(p_referral_id: chest.id)) }
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as BackendError {
            throw Self.map(error)
        }
    }

    static func map(_ error: BackendError) -> ReferralError {
        switch error {
        case .notSignedIn: return .notSignedIn
        case .network(let message): return .network(message)
        case .server(_, _, let message):
            switch message {
            case "code_not_found": return .codeNotFound
            case "own_code": return .ownCode
            case "already_redeemed": return .alreadyRedeemed
            case "account_too_old": return .accountTooOld
            case "circular_referral": return .circular
            case "not_authenticated": return .notSignedIn
            default: return .network(message)
            }
        case .invalidResponse, .decoding: return .network("Unexpected response from the server")
        }
    }
}
