import Foundation
import WalkscapeDomain

/// Shared discoveries, friend milestones, reactions and distance walked
/// together (see migration 20261102000001).
public struct SocialService: Sendable {
    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    struct Item: Encodable {
        let id: String
        let date: String
    }

    struct ItemsParams: Encodable { let p_items: [Item] }
    struct SinceParams: Encodable { let p_since: String }

    public func record(discoveries: [DiscoveryRecord]) async throws {
        guard !discoveries.isEmpty else { return }
        try await api.call("record_discoveries",
                           ItemsParams(p_items: discoveries.prefix(30).map { Item(id: $0.id, date: $0.day.isoString) }))
    }

    public func record(milestones: [DiscoveryRecord]) async throws {
        guard !milestones.isEmpty else { return }
        try await api.call("record_milestones",
                           ItemsParams(p_items: milestones.prefix(50).map { Item(id: $0.id, date: $0.day.isoString) }))
    }

    public func sharedDiscoveries(since day: LocalDay) async throws -> [SharedDiscovery] {
        struct Row: Decodable {
            let discovery_id: String
            let local_date: String
            let friend_id: String
            let friend_username: String
        }
        let rows: [Row] = try await api.call("my_shared_discoveries", SinceParams(p_since: day.isoString))
        return rows.compactMap { row in
            LocalDay(isoString: row.local_date).map {
                SharedDiscovery(discoveryID: row.discovery_id, day: $0, friendID: UserID(row.friend_id.lowercased()),
                                friendName: row.friend_username)
            }
        }
    }

    public func milestoneFeed(since day: LocalDay) async throws -> [FriendMilestone] {
        struct Row: Decodable {
            let user_id: String
            let username: String
            let avatar_id: String
            let milestone_id: String
            let achieved_on: String
            let reactions: Int
            let my_reaction: String?
        }
        let rows: [Row] = try await api.call("friend_milestone_feed", SinceParams(p_since: day.isoString))
        return rows.compactMap { row in
            LocalDay(isoString: row.achieved_on).map {
                FriendMilestone(friendID: UserID(row.user_id.lowercased()), username: row.username, avatarID: row.avatar_id,
                                milestoneID: row.milestone_id, day: $0, reactions: row.reactions,
                                myReaction: row.my_reaction.flatMap(Reaction.init(rawValue:)))
            }
        }
    }

    public func react(to milestone: FriendMilestone, with reaction: Reaction) async throws {
        struct Params: Encodable { let p_owner_id: String; let p_milestone_id: String; let p_reaction: String }
        try await api.call("react_to_milestone", Params(p_owner_id: milestone.friendID.rawValue,
                                                        p_milestone_id: milestone.milestoneID, p_reaction: reaction.rawValue))
    }

    /// Metres walked with each friend since becoming friends.
    public func walkedTogether() async throws -> [(friendID: UserID, username: String, meters: Int)] {
        struct Row: Decodable { let friend_id: String; let username: String; let meters: Int }
        let rows: [Row] = try await api.call("walked_together")
        return rows.map { (UserID($0.friend_id.lowercased()), $0.username, $0.meters) }
    }
}
