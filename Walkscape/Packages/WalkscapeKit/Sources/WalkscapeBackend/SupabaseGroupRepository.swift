import Foundation
import WalkscapeDomain

/// `GroupRepository` backed by the group database functions (members only;
/// every check happens on the server).
public struct SupabaseGroupRepository: GroupRepository {
    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    public func myGroups() async throws -> [CommunityGroup] {
        struct Row: Decodable {
            let id: String
            let name: String
            let description: String
            let emblem: String
            let join_code: String
            let member_count: Int
            let is_owner: Bool
        }
        let rows: [Row] = try await run { try await api.call("my_groups") }
        return rows.map {
            CommunityGroup(id: $0.id, name: $0.name, description: $0.description, emblem: $0.emblem, joinCode: $0.join_code,
                           memberCount: $0.member_count, isOwner: $0.is_owner)
        }
    }

    public func createGroup(requestID: UUID, name: String, description: String, emblem: String) async throws -> String {
        struct Params: Encodable { let p_request_id: String; let p_name: String; let p_description: String; let p_emblem: String }
        return try await run {
            try await api.call("create_group", Params(p_request_id: requestID.uuidString.lowercased(), p_name: name,
                                                      p_description: description, p_emblem: emblem))
        }
    }

    public func preview(code: String) async throws -> GroupPreview? {
        struct Params: Encodable { let p_code: String }
        struct Row: Decodable {
            let id: String
            let name: String
            let description: String
            let emblem: String
            let member_count: Int
            let is_member: Bool
        }
        let rows: [Row] = try await run { try await api.call("preview_group", Params(p_code: code)) }
        return rows.first.map {
            GroupPreview(id: $0.id, code: code, name: $0.name, description: $0.description, emblem: $0.emblem,
                         memberCount: $0.member_count, isMember: $0.is_member)
        }
    }

    public func join(code: String) async throws -> String {
        struct Params: Encodable { let p_code: String }
        return try await run { try await api.call("join_group", Params(p_code: code)) }
    }

    public func leave(groupID: String) async throws {
        struct Params: Encodable { let p_group_id: String }
        try await run { try await api.call("leave_group", Params(p_group_id: groupID)) }
    }

    public func remove(member: UserID, from groupID: String) async throws {
        struct Params: Encodable { let p_group_id: String; let p_user_id: String }
        try await run { try await api.call("remove_group_member", Params(p_group_id: groupID, p_user_id: member.rawValue)) }
    }

    public func update(groupID: String, name: String, description: String, emblem: String) async throws {
        struct Params: Encodable { let p_group_id: String; let p_name: String; let p_description: String; let p_emblem: String }
        try await run {
            try await api.call("update_group", Params(p_group_id: groupID, p_name: name, p_description: description, p_emblem: emblem))
        }
    }

    public func regenerateCode(groupID: String) async throws -> String {
        struct Params: Encodable { let p_group_id: String }
        return try await run { try await api.call("regenerate_group_code", Params(p_group_id: groupID)) }
    }

    public func members(groupID: String, limit: Int, offset: Int) async throws -> (members: [GroupMember], total: Int) {
        struct Params: Encodable { let p_group_id: String; let p_limit: Int; let p_offset: Int }
        struct Row: Decodable {
            let user_id: String
            let username: String
            let avatar_id: String
            let is_owner: Bool
            let joined_at: Date?
            let total: Int
        }
        let rows: [Row] = try await run {
            try await api.call("group_member_list", Params(p_group_id: groupID, p_limit: limit, p_offset: offset))
        }
        let members = rows.map {
            GroupMember(userID: UserID($0.user_id.lowercased()), username: $0.username, avatarID: $0.avatar_id,
                        isOwner: $0.is_owner, joinedAt: $0.joined_at)
        }
        return (members, rows.first?.total ?? 0)
    }

    public func leaderboard(groupID: String, period: LeaderboardPeriod, day: LocalDay, limit: Int, offset: Int) async throws
        -> GroupLeaderboardPage {
        struct Params: Encodable { let p_group_id: String; let p_period: String; let p_day: String; let p_limit: Int; let p_offset: Int }
        struct Row: Decodable {
            let user_id: String
            let username: String
            let avatar_id: String
            let rank: Int
            let steps: Int?
            let distance_meters: Int?
            let estimated: Bool
            let updated_at: Date?
            let is_me: Bool
            let total: Int
            /// Missing before migration 20261109000001.
            let under_review: Bool?
        }
        let rows: [Row] = try await run {
            try await api.call("group_leaderboard", Params(p_group_id: groupID, p_period: period.rawValue, p_day: day.isoString,
                                                           p_limit: limit, p_offset: offset))
        }
        let standings = rows.map {
            GroupStanding(userID: UserID($0.user_id.lowercased()), username: $0.username, avatarID: $0.avatar_id, rank: $0.rank,
                          steps: $0.steps, meters: $0.distance_meters, estimated: $0.estimated, updatedAt: $0.updated_at,
                          isMe: $0.is_me, underReview: $0.under_review ?? false)
        }
        return GroupLeaderboardPage(period: period, rows: standings, memberCount: rows.first?.total ?? 0, limit: limit)
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as BackendError {
            throw Self.map(error)
        }
    }

    static func map(_ error: BackendError) -> GroupError {
        switch error {
        case .notSignedIn: return .notSignedIn
        case .network(let message): return .network(message)
        case .server(_, _, let message):
            switch message {
            case "group_not_found": return .notFound
            case "group_limit": return .limitReached
            case "group_full": return .groupFull
            case "insufficient_coins": return .insufficientCoins
            case "invalid_group_name": return .invalidName
            case "invalid_group_description", "invalid_group_emblem": return .invalidDescription
            case "not_group_owner", "use_leave_group": return .notOwner
            case "no_cloud_save": return .needsCloudSave
            case "update_app": return .updateApp
            case "not_authenticated": return .notSignedIn
            default: return .network(message)
            }
        case .invalidResponse, .decoding: return .network("Unexpected response from the server")
        }
    }
}
