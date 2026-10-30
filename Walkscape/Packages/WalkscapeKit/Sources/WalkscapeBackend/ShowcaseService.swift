import Foundation
import WalkscapeDomain

/// Publishes the player's title, frame and favourite zone, and reads
/// friends' and teammates' (see migration 20261101000001).
public struct ShowcaseService: Sendable {
    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    struct Row: Decodable {
        let userID: String
        let titleID: String?
        let frameID: String?
        let favoriteZoneID: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id", titleID = "title_id", frameID = "frame_id", favoriteZoneID = "favorite_zone_id"
        }
    }

    public func publish(_ showcase: ProfileShowcase) async throws {
        struct Params: Encodable {
            let p_title_id: String
            let p_frame_id: String
            let p_favorite_zone_id: String?

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(p_title_id, forKey: .p_title_id)
                try container.encode(p_frame_id, forKey: .p_frame_id)
                // Sent as an explicit null so clearing the zone works.
                try container.encode(p_favorite_zone_id, forKey: .p_favorite_zone_id)
            }

            enum CodingKeys: String, CodingKey { case p_title_id, p_frame_id, p_favorite_zone_id }
        }
        try await api.call("set_my_showcase", Params(p_title_id: showcase.titleID, p_frame_id: showcase.frameID,
                                                     p_favorite_zone_id: showcase.favoriteZoneID))
    }

    /// Friends' and teammates' showcases, keyed by user id (lowercased, like friend ids).
    public func friends() async throws -> [UserID: PublicShowcase] {
        let rows: [Row] = try await api.call("friend_showcases")
        return Dictionary(rows.map { row in
            let id = UserID(row.userID.lowercased())
            return (id, PublicShowcase(userID: id, titleID: row.titleID, frameID: row.frameID, favoriteZoneID: row.favoriteZoneID))
        }, uniquingKeysWith: { first, _ in first })
    }
}
