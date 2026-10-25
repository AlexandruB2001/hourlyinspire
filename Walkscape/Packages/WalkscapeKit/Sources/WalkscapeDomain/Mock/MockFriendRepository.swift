import Foundation

/// In-memory friends used until the backend exists. Distances are fixed so
/// the track demonstrates clustering, far-ahead/behind indicators, stale and
/// unavailable states.
public actor MockFriendRepository: FriendRepository {
    public struct Friend: Sendable {
        public var userID: UserID
        public var username: String
        public var avatarID: String
        public var meters: Int?
        public var steps: Int?
        public var source: DistanceSource
        /// How long ago this friend last synced.
        public var updatedAgo: TimeInterval
        /// When false the friend hasn't synced at all today.
        public var syncedToday: Bool

        public init(userID: UserID, username: String, avatarID: String, meters: Int?, steps: Int?,
                    source: DistanceSource = .recorded, updatedAgo: TimeInterval, syncedToday: Bool = true) {
            self.userID = userID
            self.username = username
            self.avatarID = avatarID
            self.meters = meters
            self.steps = steps
            self.source = source
            self.updatedAgo = updatedAgo
            self.syncedToday = syncedToday
        }
    }

    private var friends: [Friend]
    private var requests: FriendRequests
    private var blocked: Set<UserID> = []
    private let catalog: ZoneCatalog
    private let createdAt: Date

    public init(friends: [Friend] = MockFriendRepository.sampleFriends, catalog: ZoneCatalog = .standard,
                now: Date = Date()) {
        self.friends = friends
        self.catalog = catalog
        self.createdAt = now
        self.requests = FriendRequests(
            incoming: [FriendRequest(id: "req-casey", userID: "u-casey", username: "Casey", avatarID: "sunny",
                                     direction: .incoming, createdAt: now.addingTimeInterval(-3_600))],
            outgoing: [FriendRequest(id: "req-jordan", userID: "u-jordan", username: "Jordan", avatarID: "frost",
                                     direction: .outgoing, createdAt: now.addingTimeInterval(-86_400))])
    }

    public static let sampleFriends: [Friend] = [
        Friend(userID: "u-alex", username: "Alex", avatarID: "sky", meters: 2_800, steps: 3_690, updatedAgo: 4 * 60),
        Friend(userID: "u-jamie", username: "Jamie", avatarID: "ember", meters: 2_100, steps: 2_950, updatedAgo: 12 * 60),
        Friend(userID: "u-taylor", username: "Taylor", avatarID: "plum", meters: 7_200, steps: 9_480, updatedAgo: 20 * 60),
        Friend(userID: "u-sam", username: "Sam", avatarID: "sunny", meters: 400, steps: 610, updatedAgo: 5 * 3_600),
        Friend(userID: "u-robin", username: "Robin", avatarID: "frost", meters: 9_600, steps: 12_800, updatedAgo: 45 * 60),
        Friend(userID: "u-riley", username: "Riley", avatarID: "fern", meters: nil, steps: nil,
               updatedAgo: 26 * 3_600, syncedToday: false),
    ]

    public func friendSummaries(for day: LocalDay, now: Date) async throws -> [FriendSummary] {
        friends.filter { !blocked.contains($0.userID) }.map { friend in
            let updatedAt = now.addingTimeInterval(-friend.updatedAgo)
            let availability = ProgressAvailability.evaluate(localDate: friend.syncedToday ? day : day.adding(days: -1),
                                                             updatedAt: updatedAt, today: day, now: now)
            let meters = availability == .unavailable ? nil : friend.meters
            return FriendSummary(userID: friend.userID, username: friend.username, avatarID: friend.avatarID,
                                 dailyDistanceMeters: meters, dailySteps: availability == .unavailable ? nil : friend.steps,
                                 distanceSource: friend.source,
                                 currentZoneID: meters.map { catalog.zone(forMeters: $0).id },
                                 updatedAt: updatedAt, progressAvailability: availability)
        }
    }

    public func friendRequests() async throws -> FriendRequests { requests }

    public func sendFriendRequest(toUsername username: String) async throws {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FriendRepositoryError.userNotFound }
        if name.caseInsensitiveCompare("me") == .orderedSame { throw FriendRepositoryError.cannotFriendYourself }
        if friends.contains(where: { $0.username.caseInsensitiveCompare(name) == .orderedSame }) {
            throw FriendRepositoryError.alreadyFriends
        }
        if (requests.incoming + requests.outgoing).contains(where: { $0.username.caseInsensitiveCompare(name) == .orderedSame }) {
            throw FriendRepositoryError.requestAlreadyPending
        }
        requests.outgoing.append(FriendRequest(id: "req-\(name.lowercased())", userID: UserID("u-\(name.lowercased())"),
                                               username: name, avatarID: AvatarCatalog.defaultID,
                                               direction: .outgoing, createdAt: Date()))
    }

    public func acceptFriendRequest(id: String) async throws {
        guard let index = requests.incoming.firstIndex(where: { $0.id == id }) else { return }
        let request = requests.incoming.remove(at: index)
        friends.append(Friend(userID: request.userID, username: request.username, avatarID: request.avatarID,
                              meters: 1_300, steps: 1_720, updatedAgo: 8 * 60))
    }

    public func declineFriendRequest(id: String) async throws {
        requests.incoming.removeAll { $0.id == id }
        requests.outgoing.removeAll { $0.id == id }
    }

    public func removeFriend(_ userID: UserID) async throws {
        friends.removeAll { $0.userID == userID }
    }

    public func blockUser(_ userID: UserID) async throws {
        blocked.insert(userID)
        friends.removeAll { $0.userID == userID }
        requests.incoming.removeAll { $0.userID == userID }
        requests.outgoing.removeAll { $0.userID == userID }
    }
}
