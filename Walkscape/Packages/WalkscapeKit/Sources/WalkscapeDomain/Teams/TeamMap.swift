import Foundation

/// The team's whole route as one long trail: a stop every 5 km of team
/// distance, from the first step to the end of the last team world, with
/// landmarks (campfire levels, expeditions, team-world zones) along the way.
public enum TeamMap {
    public static let waypointMeters = 5_000

    /// Where the route ends: the last zone of the last team world.
    public static var lengthMeters: Int {
        guard let last = TeamWorldCatalog.worlds.last else { return 0 }
        return TeamWorldCatalog.startMeters(of: last) + last.lengthMeters
    }

    public static var waypointCount: Int { lengthMeters / waypointMeters }

    /// The last stop the team has reached (0 = the start).
    public static func reachedWaypoint(teamMeters: Int) -> Int {
        min(waypointCount, max(0, teamMeters) / waypointMeters)
    }

    public struct Landmark: Identifiable, Hashable, Sendable {
        public enum Kind: String, Sendable {
            case campfire, expedition, worldZone
        }

        public let id: String
        public let kind: Kind
        public let meters: Int
        public let title: String
        public let spriteID: String
    }

    /// Every landmark on the route, in order of distance.
    public static let landmarks: [Landmark] = {
        var marks: [Landmark] = []
        for level in CampfireCatalog.levels where level.meters > 0 {
            marks.append(Landmark(id: "campfire-\(level.level)", kind: .campfire, meters: level.meters,
                                  title: "Campfire: \(level.name)", spriteID: "lantern"))
        }
        var expeditionMeters = 0
        for expedition in ExpeditionCatalog.all {
            expeditionMeters += expedition.goalMeters
            marks.append(Landmark(id: "expedition-\(expedition.id)", kind: .expedition, meters: expeditionMeters,
                                  title: expedition.name, spriteID: expedition.spriteID))
        }
        for world in TeamWorldCatalog.worlds {
            let start = TeamWorldCatalog.startMeters(of: world)
            for zone in world.zones {
                marks.append(Landmark(id: "zone-\(zone.id)", kind: .worldZone, meters: start + zone.metersFromWorldStart,
                                      title: "\(world.name): \(zone.name)", spriteID: zone.relic.spriteID))
            }
        }
        return marks.filter { $0.meters <= lengthMeters }.sorted { ($0.meters, $0.id) < ($1.meters, $1.id) }
    }()

    /// Landmarks at a stop (each landmark belongs to the nearest stop at or after it).
    public static func landmarks(atWaypoint index: Int) -> [Landmark] {
        landmarks.filter { ($0.meters + waypointMeters - 1) / waypointMeters == index }
    }

    /// The region a stop sits in: the trail before the worlds, or a team world.
    public static func world(atWaypoint index: Int) -> TeamWorld? {
        let meters = index * waypointMeters
        return TeamWorldCatalog.worlds.last { TeamWorldCatalog.startMeters(of: $0) <= meters }
    }
}

/// A small challenge that starts each time the team reaches a 5 km stop and
/// runs for the rest of that day. Everyone who walked at least 1 km that day
/// is rewarded when it's done, once per stop (so switching teams can't repeat it).
public struct WaypointChallenge: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// At least `members` people each walk `meters` today.
        case together(members: Int, meters: Int)
        /// Every member walks `meters` today.
        case everyone(meters: Int)
        /// The team walks `meters` today, all together.
        case push(meters: Int)
    }

    public let waypoint: Int
    public let kind: Kind

    /// Walked today before you share in the reward.
    public static let participationMeters = 1_000

    /// The challenge for `waypoint`, picked by a hash of the team and stop so
    /// every member sees the same one.
    public init(waypoint: Int, teamID: String, memberCount: Int) {
        self.waypoint = waypoint
        let roll = WildlifeCatalog.roll("waypoint#\(teamID)#\(waypoint)")
        let members = max(1, memberCount)
        if members == 1 || roll < 0.4 {
            kind = .push(meters: min(30_000, max(5_000, members * 3_000)))
        } else if roll < 0.75 {
            kind = .together(members: min(3, members), meters: 2_000)
        } else {
            kind = .everyone(meters: 1_000)
        }
    }

    init(waypoint: Int, kind: Kind) {
        self.waypoint = waypoint
        self.kind = kind
    }

    public var title: String {
        switch kind {
        case .together(let members, let meters):
            return "\(members) walkers, \(DistanceFormatting.kilometres(meters)) each today"
        case .everyone(let meters): return "Everyone walks \(DistanceFormatting.kilometres(meters)) today"
        case .push(let meters): return "Walk \(DistanceFormatting.kilometres(meters)) as a team today"
        }
    }

    /// Progress from members' distances today (nil = not sharing).
    public func progress(todayMeters: [Int?]) -> (done: Int, goal: Int) {
        let known = todayMeters.compactMap { $0 }
        switch kind {
        case .together(let members, let meters):
            return (min(members, known.filter { $0 >= meters }.count), members)
        case .everyone(let meters):
            return (todayMeters.filter { ($0 ?? 0) >= meters }.count, todayMeters.count)
        case .push(let meters):
            return (min(meters, known.reduce(0, +)), meters)
        }
    }

    public func isComplete(todayMeters: [Int?]) -> Bool {
        let (done, goal) = progress(todayMeters: todayMeters)
        return goal > 0 && done >= goal
    }

    /// Paid once per player for each stop number.
    public var reward: Reward { Reward(id: "waypoint-\(waypoint)", coins: 20, xp: 60) }
}

extension JournalEvents {
    public static func waypointChallenge(_ challenge: WaypointChallenge, teamName: String, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: challenge.reward.id, kind: .expedition, day: day, title: "\(teamName) cleared stop \(challenge.waypoint)!",
                     detail: challenge.title, iconID: "flag")
    }
}
