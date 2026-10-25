import Foundation
import WalkscapeDomain

public enum ProfileUpdateError: Error, Hashable, Sendable {
    case invalidUsername
    case usernameTaken
    case backend(BackendError)
}

public struct ProfileService: Sendable {
    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    /// Usernames: 3–20 lowercase letters, digits or underscores.
    public static func normalizedUsername(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        guard (3...20).contains(name.count), name.allSatisfy(allowed.contains) else { return nil }
        return name
    }

    public func myProfile() async throws -> RemoteProfile {
        try await api.call("get_my_profile")
    }

    /// Updates only the fields that are non-nil.
    public func update(username: String? = nil, avatarID: String? = nil, shareProgress: Bool? = nil) async throws -> RemoteProfile {
        struct Params: Encodable {
            let p_username: String?
            let p_avatar_id: String?
            let p_share_progress: Bool?

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(p_username, forKey: .p_username)
                try container.encodeIfPresent(p_avatar_id, forKey: .p_avatar_id)
                try container.encodeIfPresent(p_share_progress, forKey: .p_share_progress)
            }

            enum CodingKeys: String, CodingKey { case p_username, p_avatar_id, p_share_progress }
        }
        var cleanName: String?
        if let username {
            guard let normalized = Self.normalizedUsername(username) else { throw ProfileUpdateError.invalidUsername }
            cleanName = normalized
        }
        do {
            return try await api.call("update_my_profile",
                                      Params(p_username: cleanName, p_avatar_id: avatarID, p_share_progress: shareProgress))
        } catch let error as BackendError {
            switch error.serverMessage {
            case "username_taken": throw ProfileUpdateError.usernameTaken
            case "invalid_username": throw ProfileUpdateError.invalidUsername
            default: throw ProfileUpdateError.backend(error)
            }
        }
    }
}
