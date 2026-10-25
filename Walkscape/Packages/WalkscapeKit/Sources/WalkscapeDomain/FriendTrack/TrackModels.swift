import Foundation

/// Someone drawn on the shared daily track (the current user or a friend).
public struct TrackParticipant: Identifiable, Hashable, Sendable {
    public let id: UserID
    public let name: String
    public let avatarID: String
    /// Today's distance. `nil` when unavailable; such participants are listed
    /// but never placed on the track.
    public let distanceMeters: Int?
    public let isDistanceEstimated: Bool
    public let availability: ProgressAvailability
    public let currentZoneID: String?
    public let updatedAt: Date?
    public let isCurrentUser: Bool

    public init(id: UserID, name: String, avatarID: String, distanceMeters: Int?, isDistanceEstimated: Bool = false,
                availability: ProgressAvailability = .current, currentZoneID: String? = nil, updatedAt: Date? = nil,
                isCurrentUser: Bool = false) {
        self.id = id
        self.name = name
        self.avatarID = avatarID
        self.distanceMeters = availability == .unavailable ? nil : distanceMeters.map { max(0, $0) }
        self.isDistanceEstimated = isDistanceEstimated
        self.availability = availability
        self.currentZoneID = currentZoneID
        self.updatedAt = updatedAt
        self.isCurrentUser = isCurrentUser
    }

    public init(friend: FriendSummary) {
        self.init(id: friend.userID, name: friend.username, avatarID: friend.avatarID,
                  distanceMeters: friend.dailyDistanceMeters,
                  isDistanceEstimated: friend.distanceSource == .estimatedFromSteps,
                  availability: friend.progressAvailability, currentZoneID: friend.currentZoneID,
                  updatedAt: friend.updatedAt)
    }

    public var isPlaceable: Bool { distanceMeters != nil }
}

/// What the viewport centres on.
public enum TrackFocus: Hashable, Sendable {
    /// Default: the current user and the friends nearest to them.
    case currentUser
    /// A friend chosen via an indicator or a tap; centred in the viewport.
    case participant(UserID)
    /// The user dragged the track; the range stays where they left it.
    case free(centerMeters: Int, spanMeters: Int)
}

/// Visible distance window, in metres. `lower < upper` always.
public struct TrackRange: Hashable, Sendable {
    public let lower: Int
    public let upper: Int

    public init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = max(upper, lower + 1)
    }

    public var span: Int { upper - lower }
    public var center: Int { lower + span / 2 }
    public func contains(_ meters: Int) -> Bool { meters >= lower && meters <= upper }
}

public struct TrackLayoutConfiguration: Hashable, Sendable {
    public var viewportWidth: Double
    /// Width of a character sprite in points.
    public var characterWidth: Double
    /// Minimum centre-to-centre distance between two characters in one lane,
    /// so name labels never overlap.
    public var labelWidth: Double
    public var edgeInset: Double
    /// Space reserved at an edge when it shows overflow indicators.
    public var indicatorWidth: Double
    /// Smallest visible span. Stops 3 friends 20 m apart filling the screen.
    public var minimumSpanMeters: Int
    /// Largest visible span. Beyond this, friends become overflow indicators.
    public var maximumSpanMeters: Int
    /// Rows characters can be stacked into when they are close together.
    public var laneCount: Int
    /// Spans are rounded up to multiples of this to reduce scale jitter.
    public var spanStepMeters: Int
    /// Auto-fit centres are rounded to multiples of this to reduce jitter.
    public var centerStepMeters: Int

    public init(viewportWidth: Double, characterWidth: Double = 40, labelWidth: Double = 64, edgeInset: Double = 8,
                indicatorWidth: Double = 76, minimumSpanMeters: Int = 500, maximumSpanMeters: Int = 2_000,
                laneCount: Int = 3, spanStepMeters: Int = 250, centerStepMeters: Int = 50) {
        self.viewportWidth = viewportWidth
        self.characterWidth = characterWidth
        self.labelWidth = labelWidth
        self.edgeInset = edgeInset
        self.indicatorWidth = indicatorWidth
        self.minimumSpanMeters = max(1, minimumSpanMeters)
        self.maximumSpanMeters = max(self.minimumSpanMeters, maximumSpanMeters)
        self.laneCount = max(1, laneCount)
        self.spanStepMeters = max(1, spanStepMeters)
        self.centerStepMeters = max(1, centerStepMeters)
    }
}

public struct TrackLayoutInput: Sendable {
    /// Everyone on the track, including the current user.
    public var participants: [TrackParticipant]
    public var focus: TrackFocus
    public var configuration: TrackLayoutConfiguration
    /// The range currently on screen. When it still fits, it is kept, so
    /// small distance updates don't make the track jump.
    public var previousRange: TrackRange?

    public init(participants: [TrackParticipant], focus: TrackFocus = .currentUser,
                configuration: TrackLayoutConfiguration, previousRange: TrackRange? = nil) {
        self.participants = participants
        self.focus = focus
        self.configuration = configuration
        self.previousRange = previousRange
    }
}

/// Where a visible character is drawn.
public struct CharacterPosition: Identifiable, Hashable, Sendable {
    public let participant: TrackParticipant
    /// Horizontal centre in points, after de-overlapping.
    public let x: Double
    /// Horizontal centre in points at the exact distance (before de-overlapping).
    public let exactX: Double
    /// 0 = front row. Close characters are stacked into back rows.
    public let lane: Int
    public let isFocused: Bool

    public var id: UserID { participant.id }
    /// True when the character had to be shifted sideways to avoid overlap.
    public var isNudged: Bool { abs(x - exactX) > 0.5 }
}

public enum OverflowDirection: String, Hashable, Sendable {
    /// Lower distances (left edge).
    case behind
    /// Higher distances (right edge).
    case ahead
}

/// A compact edge badge for participants outside the visible range.
public struct OverflowIndicator: Identifiable, Hashable, Sendable {
    public let direction: OverflowDirection
    /// Nearest to the viewport first.
    public let members: [TrackParticipant]
    /// Tapping focuses this participant (the nearest member).
    public let targetUserID: UserID
    /// Nearest member's distance minus the current user's distance.
    public let gapFromCurrentUserMeters: Int
    public let label: String
    public let accessibilityLabel: String

    public var id: String { "\(direction.rawValue)-" + members.map(\.id.rawValue).joined(separator: ",") }
    public var isGroup: Bool { members.count > 1 }
    public var includesCurrentUser: Bool { members.contains(where: \.isCurrentUser) }
}

/// The computed presentation of the track. Purely derived; never persisted
/// and never written back into anybody's progress.
public struct TrackViewport: Hashable, Sendable {
    public let focus: TrackFocus
    public let focusedUserID: UserID?
    public let range: TrackRange
    /// Points per metre.
    public let distanceScale: Double
    /// x of `range.lower` / `range.upper`.
    public let plotMinX: Double
    public let plotMaxX: Double
    public let characterPositions: [CharacterPosition]
    public let leftOverflow: [OverflowIndicator]
    public let rightOverflow: [OverflowIndicator]
    /// Participants without today's data. Listed, never placed.
    public let unavailableParticipants: [TrackParticipant]
    public let isCurrentUserVisible: Bool

    public var visibleMinimumMeters: Int { range.lower }
    public var visibleMaximumMeters: Int { range.upper }
    public var leftOverflowFriends: [TrackParticipant] { leftOverflow.flatMap(\.members) }
    public var rightOverflowFriends: [TrackParticipant] { rightOverflow.flatMap(\.members) }

    public func x(forMeters meters: Int) -> Double {
        plotMinX + Double(meters - range.lower) * distanceScale
    }

    public func position(for id: UserID) -> CharacterPosition? {
        characterPositions.first { $0.id == id }
    }
}
