import Foundation

public enum FriendRepositoryError: Error, Hashable, Sendable {
    case userNotFound
    case cannotFriendYourself
    case alreadyFriends
    case requestAlreadyPending
    case notConfigured
    case notSignedIn
    case network(String)
}

public struct FriendRequests: Hashable, Sendable {
    public var incoming: [FriendRequest]
    public var outgoing: [FriendRequest]

    public init(incoming: [FriendRequest] = [], outgoing: [FriendRequest] = []) {
        self.incoming = incoming
        self.outgoing = outgoing
    }
}

/// Friends and their daily summaries. The mock implementation is used until
/// the Supabase repository is configured (Milestone 4).
public protocol FriendRepository: Sendable {
    func friendSummaries(for day: LocalDay, now: Date) async throws -> [FriendSummary]
    func friendRequests() async throws -> FriendRequests
    func sendFriendRequest(toUsername username: String) async throws
    func acceptFriendRequest(id: String) async throws
    func declineFriendRequest(id: String) async throws
    func removeFriend(_ userID: UserID) async throws
    func blockUser(_ userID: UserID) async throws
}
