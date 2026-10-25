import Foundation

/// The track's focus state machine. Holds only presentation state.
///
/// - The default is `.currentUser`.
/// - A chosen friend stays focused until the user picks someone else, taps
///   "Back to me", or the friend disappears from the data.
/// - While the user drags (`.free`), data refreshes never recentre the track.
public struct TrackFocusController: Hashable, Sendable {
    public private(set) var focus: TrackFocus = .currentUser

    public init(focus: TrackFocus = .currentUser) {
        self.focus = focus
    }

    public var showsBackToMe: Bool { focus != .currentUser }

    public var focusedFriendID: UserID? {
        if case .participant(let id) = focus { return id }
        return nil
    }

    public mutating func focus(on id: UserID, currentUserID: UserID) {
        focus = id == currentUserID ? .currentUser : .participant(id)
    }

    public mutating func select(_ indicator: OverflowIndicator, currentUserID: UserID) {
        focus(on: indicator.targetUserID, currentUserID: currentUserID)
    }

    public mutating func backToMe() {
        focus = .currentUser
    }

    /// Converts a horizontal drag into a free range. `deltaMeters` is positive
    /// when the track should move toward higher distances.
    public mutating func pan(from range: TrackRange, deltaMeters: Int) {
        focus = .free(centerMeters: max(0, range.center + deltaMeters), spanMeters: range.span)
    }

    /// Call after every data refresh. Drops focus on a friend who is gone or
    /// has no data today; otherwise focus is preserved.
    public mutating func reconcile(with participants: [TrackParticipant]) {
        guard case .participant(let id) = focus else { return }
        if !participants.contains(where: { $0.id == id && $0.isPlaceable }) {
            focus = .currentUser
        }
    }
}
