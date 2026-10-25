import Foundation
import WalkscapeDomain

/// A walker's public profile as stored by the backend.
public struct RemoteProfile: Decodable, Hashable, Sendable {
    public let id: UserID
    public let username: String
    public let avatarID: String
    public let shareProgress: Bool

    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarID = "avatar_id"
        case shareProgress = "share_progress"
    }

    public init(id: UserID, username: String, avatarID: String, shareProgress: Bool) {
        self.id = id
        self.username = username
        self.avatarID = avatarID
        self.shareProgress = shareProgress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UserID(try container.decode(String.self, forKey: .id).lowercased())
        username = try container.decode(String.self, forKey: .username)
        avatarID = try container.decode(String.self, forKey: .avatarID)
        shareProgress = try container.decode(Bool.self, forKey: .shareProgress)
    }
}

/// Row from `friend_daily_summaries`.
struct FriendSummaryRow: Decodable {
    let userID: String
    let username: String
    let avatarID: String
    let localDate: String?
    let steps: Int?
    let distanceMeters: Int?
    let distanceSource: DistanceSource?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", username, avatarID = "avatar_id", localDate = "local_date", steps
        case distanceMeters = "distance_meters", distanceSource = "distance_source", updatedAt = "updated_at"
    }
}

/// Row from `pending_friend_requests`.
struct PendingRequestRow: Decodable {
    let id: String
    let userID: String
    let username: String
    let avatarID: String
    let direction: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userID = "user_id", username, avatarID = "avatar_id", direction, createdAt = "created_at"
    }
}
