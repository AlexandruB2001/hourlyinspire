import Foundation

/// Whether a friend's daily numbers can be trusted as "today".
public enum ProgressAvailability: String, Codable, Sendable, Hashable {
    /// Today's data, updated recently.
    case current
    /// Today's data, but not refreshed for a while.
    case stale
    /// No data for today (never synced today, or sharing turned off).
    case unavailable

    public static let staleInterval: TimeInterval = 3 * 60 * 60

    public static func evaluate(localDate: LocalDay?, updatedAt: Date?, today: LocalDay, now: Date,
                                staleAfter: TimeInterval = staleInterval) -> ProgressAvailability {
        guard let localDate, let updatedAt, localDate == today else { return .unavailable }
        return now.timeIntervalSince(updatedAt) > staleAfter ? .stale : .current
    }
}

/// What the app may know about a friend for one day: aggregate totals only.
public struct FriendSummary: Identifiable, Codable, Hashable, Sendable {
    public var userID: UserID
    public var username: String
    public var avatarID: String
    public var dailyDistanceMeters: Int?
    public var dailySteps: Int?
    public var distanceSource: DistanceSource
    public var currentZoneID: String?
    public var updatedAt: Date?
    public var progressAvailability: ProgressAvailability

    public var id: UserID { userID }

    public init(userID: UserID, username: String, avatarID: String, dailyDistanceMeters: Int?, dailySteps: Int?,
                distanceSource: DistanceSource = .recorded, currentZoneID: String?, updatedAt: Date?,
                progressAvailability: ProgressAvailability) {
        self.userID = userID
        self.username = username
        self.avatarID = avatarID
        self.dailyDistanceMeters = dailyDistanceMeters
        self.dailySteps = dailySteps
        self.distanceSource = distanceSource
        self.currentZoneID = currentZoneID
        self.updatedAt = updatedAt
        self.progressAvailability = progressAvailability
    }
}

public struct FriendRequest: Identifiable, Codable, Hashable, Sendable {
    public enum Direction: String, Codable, Sendable { case incoming, outgoing }
    public var id: String
    public var userID: UserID
    public var username: String
    public var avatarID: String
    public var direction: Direction
    public var createdAt: Date

    public init(id: String, userID: UserID, username: String, avatarID: String, direction: Direction, createdAt: Date) {
        self.id = id
        self.userID = userID
        self.username = username
        self.avatarID = avatarID
        self.direction = direction
        self.createdAt = createdAt
    }
}
