import Foundation

public struct LeaderboardEntry: Identifiable, Hashable, Sendable {
    public let participant: TrackParticipant
    /// Competition rank (1, 1, 3…). `nil` when unranked.
    public let rank: Int?
    public let unrankedReason: UnrankedReason?

    public enum UnrankedReason: String, Hashable, Sendable {
        case noDataToday
        case estimatedDistance
    }

    public var id: UserID { participant.id }
}

/// Daily ranking. Only recorded distances for today are ranked; estimated
/// distances are shown but not ranked so they never mix with recorded ones.
public enum Leaderboard {
    public static func rank(_ participants: [TrackParticipant]) -> [LeaderboardEntry] {
        var seen = Set<UserID>()
        let unique = participants.filter { seen.insert($0.id).inserted }
        let ranked = unique.filter { $0.isPlaceable && !$0.isDistanceEstimated }.sorted {
            let (a, b) = ($0.distanceMeters!, $1.distanceMeters!)
            if a != b { return a > b }
            if $0.isCurrentUser != $1.isCurrentUser { return $0.isCurrentUser }
            return $0.name != $1.name ? $0.name < $1.name : $0.id < $1.id
        }
        var entries: [LeaderboardEntry] = []
        for (index, participant) in ranked.enumerated() {
            let rank: Int
            if index > 0, ranked[index - 1].distanceMeters == participant.distanceMeters, let previous = entries.last?.rank {
                rank = previous
            } else {
                rank = index + 1
            }
            entries.append(LeaderboardEntry(participant: participant, rank: rank, unrankedReason: nil))
        }
        let estimated = unique.filter { $0.isPlaceable && $0.isDistanceEstimated }
            .sorted { $0.distanceMeters! > $1.distanceMeters! }
        let missing = unique.filter { !$0.isPlaceable }.sorted { $0.name < $1.name }
        entries += estimated.map { LeaderboardEntry(participant: $0, rank: nil, unrankedReason: .estimatedDistance) }
        entries += missing.map { LeaderboardEntry(participant: $0, rank: nil, unrankedReason: .noDataToday) }
        return entries
    }
}
