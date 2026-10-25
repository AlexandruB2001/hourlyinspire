import Foundation
import WalkscapeDomain

/// `FriendRepository` backed by the Walkscape database functions.
public struct SupabaseFriendRepository: FriendRepository {
    private let api: SupabaseAPI
    private let catalog: ZoneCatalog

    public init(api: SupabaseAPI, catalog: ZoneCatalog = .standard) {
        self.api = api
        self.catalog = catalog
    }

    public func friendSummaries(for day: LocalDay, now: Date) async throws -> [FriendSummary] {
        struct Params: Encodable { let p_local_date: String }
        let rows: [FriendSummaryRow] = try await run { try await api.call("friend_daily_summaries", Params(p_local_date: day.isoString)) }
        return rows.map { row in
            let rowDay = row.localDate.flatMap(LocalDay.init(isoString:))
            let availability = ProgressAvailability.evaluate(localDate: rowDay, updatedAt: row.updatedAt, today: day, now: now)
            let meters = availability == .unavailable ? nil : row.distanceMeters
            return FriendSummary(userID: UserID(row.userID.lowercased()), username: row.username, avatarID: row.avatarID,
                                 dailyDistanceMeters: meters,
                                 dailySteps: availability == .unavailable ? nil : row.steps,
                                 distanceSource: row.distanceSource ?? .unavailable,
                                 currentZoneID: meters.map { catalog.zone(forMeters: $0).id },
                                 updatedAt: row.updatedAt,
                                 progressAvailability: availability)
        }
    }

    public func friendRequests() async throws -> FriendRequests {
        let rows: [PendingRequestRow] = try await run { try await api.call("pending_friend_requests") }
        var requests = FriendRequests()
        for row in rows {
            let request = FriendRequest(id: row.id.lowercased(), userID: UserID(row.userID.lowercased()),
                                        username: row.username, avatarID: row.avatarID,
                                        direction: row.direction == "incoming" ? .incoming : .outgoing,
                                        createdAt: row.createdAt)
            if request.direction == .incoming { requests.incoming.append(request) } else { requests.outgoing.append(request) }
        }
        return requests
    }

    public func sendFriendRequest(toUsername username: String) async throws {
        struct Params: Encodable { let p_username: String }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FriendRepositoryError.userNotFound }
        _ = try await run { try await api.call("send_friend_request", Params(p_username: name)) as IgnoredResult }
    }

    public func acceptFriendRequest(id: String) async throws {
        struct Params: Encodable { let p_request_id: String; let p_accept: Bool }
        try await run { try await api.call("respond_to_friend_request", Params(p_request_id: id, p_accept: true)) }
    }

    /// Declines an incoming request or cancels an outgoing one.
    public func declineFriendRequest(id: String) async throws {
        struct Params: Encodable { let p_request_id: String }
        try await run { try await api.call("delete_friend_request", Params(p_request_id: id)) }
    }

    public func removeFriend(_ userID: UserID) async throws {
        struct Params: Encodable { let p_friend_id: String }
        try await run { try await api.call("remove_friend", Params(p_friend_id: userID.rawValue)) }
    }

    public func blockUser(_ userID: UserID) async throws {
        struct Params: Encodable { let p_user_id: String }
        try await run { try await api.call("block_user", Params(p_user_id: userID.rawValue)) }
    }

    /// Maps backend errors to the repository's error vocabulary.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as BackendError {
            throw Self.map(error)
        }
    }

    static func map(_ error: BackendError) -> FriendRepositoryError {
        switch error {
        case .notSignedIn: return .notSignedIn
        case .network(let message): return .network(message)
        case .server(_, _, let message):
            switch message {
            case "user_not_found": return .userNotFound
            case "cannot_friend_self": return .cannotFriendYourself
            case "already_friends": return .alreadyFriends
            case "request_already_pending": return .requestAlreadyPending
            case "not_authenticated": return .notSignedIn
            default: return .network(message)
            }
        case .invalidResponse, .decoding: return .network("Unexpected response from the server")
        }
    }
}

/// Decodes (and discards) any JSON result.
struct IgnoredResult: Decodable {
    init(from decoder: Decoder) throws {}
}
