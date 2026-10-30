import Foundation

/// The team's shared campsite. It grows with the team's lifetime distance
/// (from the team ledger, which never goes down) and finished expeditions.
public struct CampfireLevel: Identifiable, Hashable, Sendable {
    public let level: Int
    public let name: String
    public let detail: String
    /// Team distance needed.
    public let meters: Int
    /// Expeditions the team must have finished too.
    public let expeditions: Int

    public var id: Int { level }

    /// Paid once per player for each level they see their campsite reach.
    public var reward: Reward { Reward(id: "campfire-level-\(level)", coins: level * 20, xp: level * 60) }
}

public struct CampsiteDecoration: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable {
        /// Unlocked by the Campfire level.
        case campfire
        /// From the Cozy Campsite Decor bundle.
        case bundle
        /// For Walkscape Plus members.
        case plus
    }

    public let id: String
    public let name: String
    public let unlockLevel: Int
    public let source: Source

    public init(id: String, name: String, unlockLevel: Int, source: Source = .campfire) {
        self.id = id
        self.name = name
        self.unlockLevel = unlockLevel
        self.source = source
    }
}

public enum CampfireCatalog {
    public static let levels: [CampfireLevel] = [
        CampfireLevel(level: 1, name: "Small Campfire", detail: "A little fire and a log to sit on.", meters: 0, expeditions: 0),
        CampfireLevel(level: 2, name: "Tent & Lantern", detail: "A cosy tent and a lantern for the long evenings.",
                      meters: 50_000, expeditions: 1),
        CampfireLevel(level: 3, name: "Gathering Place", detail: "Wooden benches, bunting and a cooking pot.",
                      meters: 150_000, expeditions: 2),
        CampfireLevel(level: 4, name: "Camp Village", detail: "Little cabins and a lookout over the trail.",
                      meters: 400_000, expeditions: 3),
        CampfireLevel(level: 5, name: "Expedition Headquarters", detail: "A great lodge with banners for every adventure.",
                      meters: 1_000_000, expeditions: 4),
    ]

    public static let decorations: [CampsiteDecoration] = [
        CampsiteDecoration(id: "flowers", name: "Wildflowers", unlockLevel: 1),
        CampsiteDecoration(id: "mushrooms", name: "Mushroom Ring", unlockLevel: 1),
        CampsiteDecoration(id: "lantern", name: "Lantern Post", unlockLevel: 2),
        CampsiteDecoration(id: "signpost", name: "Signpost", unlockLevel: 2),
        CampsiteDecoration(id: "bunting", name: "Bunting", unlockLevel: 3),
        CampsiteDecoration(id: "pumpkins", name: "Pumpkins", unlockLevel: 3),
        CampsiteDecoration(id: "fireflies", name: "Firefly Jars", unlockLevel: 4),
        CampsiteDecoration(id: "totem", name: "Trail Totem", unlockLevel: 4),
        CampsiteDecoration(id: "banner", name: "Expedition Banner", unlockLevel: 5),
        CampsiteDecoration(id: "telescope", name: "Star Telescope", unlockLevel: 5),
    ] + premiumDecorations + plusDecorations

    /// Cozy Campsite Decor bundle. Anyone in the team sees them once a member places them.
    public static let premiumDecorations: [CampsiteDecoration] = [
        CampsiteDecoration(id: "hammock", name: "Hammock", unlockLevel: 1, source: .bundle),
        CampsiteDecoration(id: "string-lights", name: "String Lights", unlockLevel: 1, source: .bundle),
        CampsiteDecoration(id: "cocoa-stand", name: "Hot Cocoa Stand", unlockLevel: 1, source: .bundle),
    ]

    /// Walkscape Plus decorations.
    public static let plusDecorations: [CampsiteDecoration] = [
        CampsiteDecoration(id: "fountain", name: "Wishing Fountain", unlockLevel: 1, source: .plus),
        CampsiteDecoration(id: "lantern-arch", name: "Lantern Arch", unlockLevel: 1, source: .plus),
    ]

    public static let maxPlaced = 6

    public static func level(teamMeters: Int, expeditions: Int) -> CampfireLevel {
        levels.last { teamMeters >= $0.meters && expeditions >= $0.expeditions } ?? levels[0]
    }

    public static func next(after level: CampfireLevel) -> CampfireLevel? {
        levels.first { $0.level == level.level + 1 }
    }

    public static func unlockedDecorations(at level: CampfireLevel) -> [CampsiteDecoration] {
        decorations.filter { $0.unlockLevel <= level.level }
    }

    /// Placed decorations that are unlocked and known, in order, without repeats.
    public static func valid(_ placed: [String], at level: CampfireLevel) -> [String] {
        let unlocked = Set(unlockedDecorations(at: level).map(\.id))
        var seen = Set<String>()
        return placed.filter { unlocked.contains($0) && seen.insert($0).inserted }.prefix(maxPlaced).map { $0 }
    }
}

/// The team's campsite as shown to every member.
public struct Campsite: Hashable, Sendable {
    public let level: CampfireLevel
    public let teamMeters: Int
    public let expeditions: Int
    public let decorations: [String]

    public init(teamMeters: Int, expeditions: Int, placed: [String]) {
        self.teamMeters = max(0, teamMeters)
        self.expeditions = max(0, expeditions)
        level = CampfireCatalog.level(teamMeters: teamMeters, expeditions: expeditions)
        decorations = CampfireCatalog.valid(placed, at: level)
    }

    public var nextLevel: CampfireLevel? { CampfireCatalog.next(after: level) }

    /// 0...1 toward the next level's distance.
    public var fractionToNext: Double {
        guard let next = nextLevel else { return 1 }
        let span = Double(next.meters - level.meters)
        return min(1, max(0, Double(teamMeters - level.meters) / span))
    }

    /// Levels the player can be paid for (each id pays once per player, ever,
    /// so moving between teams can't collect them again).
    public var rewards: [Reward] { CampfireCatalog.levels.filter { $0.level > 1 && $0.level <= level.level }.map(\.reward) }
}

/// Someone's share of the team's lifetime distance.
public struct TeamContribution: Identifiable, Hashable, Sendable {
    public let userID: UserID
    public let username: String
    public let avatarID: String
    public let meters: Int
    public let isMember: Bool

    public init(userID: UserID, username: String, avatarID: String, meters: Int, isMember: Bool) {
        self.userID = userID
        self.username = username
        self.avatarID = avatarID
        self.meters = meters
        self.isMember = isMember
    }

    public var id: UserID { userID }
}

extension JournalEvents {
    public static func campfire(_ level: CampfireLevel, teamName: String, on day: LocalDay) -> JournalEntry {
        JournalEntry(id: "campfire-level-\(level.level)", kind: .team, day: day,
                     title: "\(teamName)'s campsite: \(level.name)", detail: level.detail, iconID: "lantern")
    }
}
