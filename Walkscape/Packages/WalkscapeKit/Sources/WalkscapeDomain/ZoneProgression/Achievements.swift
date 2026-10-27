import Foundation

public struct Achievement: Identifiable, Hashable, Sendable {
    public enum Requirement: Hashable, Sendable {
        case singleDayMeters(Int)
        case lifetimeMeters(Int)
        case collectedItems(Int)
        case activeDays(count: Int, minimumMeters: Int)
    }

    public let id: String
    public let name: String
    public let detail: String
    public let spriteID: String
    public let requirement: Requirement

    public init(id: String, name: String, detail: String, spriteID: String, requirement: Requirement) {
        self.id = id
        self.name = name
        self.detail = detail
        self.spriteID = spriteID
        self.requirement = requirement
    }

    public func isUnlocked(by state: ProgressionState) -> Bool {
        progress(for: state) >= 1
    }

    /// 0...1 progress toward the requirement.
    public func progress(for state: ProgressionState) -> Double {
        func ratio(_ value: Int, _ target: Int) -> Double { target <= 0 ? 1 : min(1, Double(value) / Double(target)) }
        switch requirement {
        case .singleDayMeters(let target): return ratio(state.bestDayMeters, target)
        case .lifetimeMeters(let target): return ratio(state.lifetimeMeters, target)
        case .collectedItems(let target): return ratio(state.collectedItemIDs.count, target)
        case .activeDays(let count, let minimum): return ratio(state.activeDays(minimumMeters: minimum), count)
        }
    }
}

public enum AchievementCatalog {
    public static let standard: [Achievement] = [
        Achievement(id: "first-steps", name: "First Steps", detail: "Walk 1 km in a day.",
                    spriteID: "boot", requirement: .singleDayMeters(1_000)),
        Achievement(id: "trailblazer", name: "Trailblazer", detail: "Reach Hearth Village in a single day (5 km).",
                    spriteID: "lantern", requirement: .singleDayMeters(5_000)),
        Achievement(id: "summiteer", name: "Summiteer", detail: "Reach the Summit in a single day (9 km).",
                    spriteID: "flag", requirement: .singleDayMeters(9_000)),
        // Kept its id from when the map ended at 10 km, so existing unlocks stay valid.
        Achievement(id: "beyond", name: "Double Digits", detail: "Walk 10 km in a single day.",
                    spriteID: "star", requirement: .singleDayMeters(10_000)),
        Achievement(id: "lightkeeper", name: "Lightkeeper", detail: "Reach Lighthouse Point in a single day (19 km).",
                    spriteID: "spyglass", requirement: .singleDayMeters(19_000)),
        Achievement(id: "off-the-map", name: "Off the Map", detail: "Walk 20 km in a single day.",
                    spriteID: "starfall", requirement: .singleDayMeters(20_000)),
        Achievement(id: "regular", name: "Regular Rambler", detail: "Walk at least 1 km on 3 different days.",
                    spriteID: "boot", requirement: .activeDays(count: 3, minimumMeters: 1_000)),
        Achievement(id: "wanderer", name: "Wanderer", detail: "Walk 25 km in total.",
                    spriteID: "compass", requirement: .lifetimeMeters(25_000)),
        Achievement(id: "marathoner", name: "Marathoner", detail: "Walk a marathon's distance in total (42.2 km).",
                    spriteID: "medal", requirement: .lifetimeMeters(42_195)),
        Achievement(id: "collector", name: "Collector", detail: "Find 5 discoveries.",
                    spriteID: "pouch", requirement: .collectedItems(5)),
        Achievement(id: "completionist", name: "Cartographer", detail: "Find 10 discoveries.",
                    spriteID: "map", requirement: .collectedItems(10)),
        Achievement(id: "curator", name: "Curator", detail: "Find all 20 discoveries.",
                    spriteID: "chest", requirement: .collectedItems(20)),
    ]
}
