import Foundation

// MARK: - Seasons

/// The season shown in the world. Uses the meteorological calendar
/// (Dec–Feb winter…), flipped for the southern hemisphere.
public enum Season: String, CaseIterable, Codable, Sendable {
    case spring, summer, autumn, winter

    public var displayName: String { rawValue.capitalized }

    public static func of(_ day: LocalDay, southernHemisphere: Bool = false) -> Season {
        let month = southernHemisphere ? ((day.month + 5) % 12) + 1 : day.month
        switch month {
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        case 9, 10, 11: return .autumn
        default: return .winter
        }
    }

    /// A rough guess from the time zone (Australia, New Zealand, South America, southern Africa).
    public static func isSouthernHemisphere(_ timeZone: TimeZone) -> Bool {
        let id = timeZone.identifier
        let southern = ["Australia/", "Pacific/Auckland", "Pacific/Chatham", "America/Argentina", "America/Santiago",
                        "America/Sao_Paulo", "America/Montevideo", "America/Asuncion", "America/La_Paz", "America/Lima",
                        "Africa/Johannesburg", "Africa/Maputo", "Africa/Harare", "Africa/Windhoek", "Indian/Mauritius",
                        "Antarctica/"]
        return southern.contains { id.hasPrefix($0) }
    }
}

// MARK: - Events

/// A small happening in one of the zones: a shooting star, a merchant, a
/// rainbow. Which events happen on a day is fixed for that day (the same for
/// everyone), and each one can be found once per day by reaching its zone.
public struct WorldEvent: Identifiable, Hashable, Sendable {
    public enum Window: Hashable, Sendable {
        case anyTime
        /// Local time from 17:00.
        case evening
        case season(Season)
        case eveningIn(Season)
    }

    /// Something extra the event gives, besides coins and XP.
    public enum Bonus: Hashable, Sendable {
        case none
        case creature(String)
        case treasure
        /// A free shop item you don't own, of at most this rarity.
        case merchantGift(Rarity)
    }

    public let id: String
    public let name: String
    public let detail: String
    /// Zones it can appear in. Empty means "a zone you've already explored".
    public let zoneIDs: [String]
    public let rarity: Rarity
    public let window: Window
    public let coins: Int
    public let xp: Int
    public let bonus: Bonus
    public let spriteID: String

    public init(id: String, name: String, detail: String, zoneIDs: [String], rarity: Rarity, window: Window = .anyTime,
                coins: Int, xp: Int, bonus: Bonus = .none, spriteID: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.zoneIDs = zoneIDs
        self.rarity = rarity
        self.window = window
        self.coins = coins
        self.xp = xp
        self.bonus = bonus
        self.spriteID = spriteID
    }

    /// Chance per day that the event happens at all.
    public var dailyChance: Double {
        switch rarity {
        case .common: return 0.25
        case .rare: return 0.10
        case .epic: return 0.05
        case .legendary: return 0.02
        }
    }

    public func isOpen(season: Season, hour: Int) -> Bool {
        switch window {
        case .anyTime: return true
        case .evening: return hour >= 17
        case .season(let s): return s == season
        case .eveningIn(let s): return s == season && hour >= 17
        }
    }
}

/// One event on one day, in one zone.
public struct ScheduledEvent: Identifiable, Hashable, Sendable {
    public let event: WorldEvent
    public let day: LocalDay
    public let zoneID: String

    public var id: String { "event-\(event.id)-\(day.isoString)" }
    public var reward: Reward { Reward(id: id, coins: event.coins, xp: event.xp) }
}

public enum WorldEventCatalog {
    public static let all: [WorldEvent] = [
        WorldEvent(id: "shooting-star", name: "Shooting Star", detail: "A star streaked over Starlight Pass and landed nearby.",
                   zoneIDs: ["starlight-pass"], rarity: .rare, window: .evening, coins: 25, xp: 80, bonus: .treasure,
                   spriteID: "starfall"),
        WorldEvent(id: "merchant", name: "Travelling Merchant", detail: "A merchant's cart rattled into Hearth Village with a gift.",
                   zoneIDs: ["village"], rarity: .common, coins: 10, xp: 40, bonus: .merchantGift(.rare), spriteID: "pouch"),
        WorldEvent(id: "fireflies", name: "Firefly Night", detail: "The whole marsh lit up with fireflies.",
                   zoneIDs: ["firefly-marsh"], rarity: .common, window: .eveningIn(.summer), coins: 15, xp: 50,
                   bonus: .creature("firefly-sprite"), spriteID: "jar"),
        WorldEvent(id: "rainbow", name: "Rainbow", detail: "A rainbow arched right over the path after the rain.",
                   zoneIDs: ["riverside", "rolling-hills", "lakeside", "blossom-orchard"], rarity: .common,
                   window: .season(.spring), coins: 15, xp: 50, spriteID: "feather"),
        WorldEvent(id: "footprints", name: "Mysterious Footprints", detail: "Tiny footprints led off the path... to a sleepy owl.",
                   zoneIDs: ["pine-forest"], rarity: .rare, coins: 20, xp: 60, bonus: .creature("owl"), spriteID: "boot"),
        WorldEvent(id: "forest-spirit", name: "Forest Spirit", detail: "A glowing spirit drifted between the mossy giants and smiled.",
                   zoneIDs: ["cloud-forest"], rarity: .legendary, coins: 60, xp: 200, bonus: .creature("spirit"),
                   spriteID: "mushroom"),
        WorldEvent(id: "lost-chest", name: "Lost Chest", detail: "An old chest turned up somewhere you've walked before.",
                   zoneIDs: [], rarity: .rare, coins: 30, xp: 80, bonus: .treasure, spriteID: "chest"),
        WorldEvent(id: "aurora", name: "Winter Aurora", detail: "Green ribbons of light danced over the snowy ridge.",
                   zoneIDs: ["snowy-ridge", "starlight-pass"], rarity: .rare, window: .eveningIn(.winter), coins: 25, xp: 80,
                   spriteID: "snowflake"),
        WorldEvent(id: "blossom-festival", name: "Blossom Festival", detail: "Lanterns and petals filled the orchard.",
                   zoneIDs: ["blossom-orchard"], rarity: .common, window: .season(.spring), coins: 15, xp: 50,
                   bonus: .creature("butterfly"), spriteID: "cherry"),
        WorldEvent(id: "harvest-moon", name: "Harvest Moon", detail: "A huge orange moon rose over the maple woods.",
                   zoneIDs: ["maple-woods"], rarity: .common, window: .eveningIn(.autumn), coins: 15, xp: 50,
                   spriteID: "maple"),
        WorldEvent(id: "whale-song", name: "Whale Song", detail: "A whale breached in the sunset beyond the lighthouse.",
                   zoneIDs: ["lighthouse-point"], rarity: .epic, window: .evening, coins: 40, xp: 120,
                   bonus: .creature("whale"), spriteID: "bottle"),
        WorldEvent(id: "crystal-bloom", name: "Crystal Bloom", detail: "The cave crystals bloomed with light all at once.",
                   zoneIDs: ["crystal-caves"], rarity: .rare, coins: 20, xp: 60, bonus: .creature("wisp"), spriteID: "crystal"),
    ]

    public static let maxPerDay = 2

    public static func event(withID id: String) -> WorldEvent? { all.first { $0.id == id } }

    /// The day's events: each rolls its chance (fixed for the day), at most
    /// `maxPerDay` happen, and "lost chest" picks one of the zones you had
    /// already explored before today.
    public static func schedule(for day: LocalDay, season: Season, exploredZoneIDs: Set<String>,
                                catalog: ZoneCatalog = .standard) -> [ScheduledEvent] {
        let candidates = all.compactMap { event -> (ScheduledEvent, Double)? in
            if case .season(let s) = event.window, s != season { return nil }
            if case .eveningIn(let s) = event.window, s != season { return nil }
            let roll = WildlifeCatalog.roll("event#\(day.isoString)#\(event.id)")
            guard roll < event.dailyChance else { return nil }
            let zones = event.zoneIDs.isEmpty
                ? catalog.zones.map(\.id).filter { exploredZoneIDs.contains($0) && $0 != catalog.zones.first?.id }
                : event.zoneIDs
            guard !zones.isEmpty else { return nil }
            let pick = Int(WildlifeCatalog.roll("event-zone#\(day.isoString)#\(event.id)") * Double(zones.count))
            return (ScheduledEvent(event: event, day: day, zoneID: zones[min(pick, zones.count - 1)]), roll)
        }
        // The rarest-rolling events win when more than the daily limit come up.
        return candidates.sorted { $0.1 < $1.1 }.prefix(maxPerDay).map(\.0)
    }
}

extension JournalEvents {
    public static func worldEvent(_ scheduled: ScheduledEvent, zoneName: String) -> JournalEntry {
        JournalEntry(id: scheduled.id, kind: .event, day: scheduled.day, title: "\(scheduled.event.name) in \(zoneName)",
                     detail: scheduled.event.detail, iconID: scheduled.event.spriteID)
    }
}
