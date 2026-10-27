import Foundation

/// The visual environment a zone is drawn with. Several zones may share a biome.
public enum Biome: String, Codable, Sendable, Hashable, CaseIterable {
    case meadow, riverside, pineForest, rollingHills, lakeside
    case village, crystalCaves, snowyRidge, cloudForest, summit
    // The far side of the Summit, down to the coast.
    case starlightPass, hotSprings, autumnWoods, bambooGrove, blossomOrchard
    case lavenderFields, redCanyon, fireflyMarsh, sandyShore, lighthousePoint
}

/// A permanent discovery found the first time a zone is reached.
public struct Collectible: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    /// Key into the pixel-art item sprite sheet.
    public var spriteID: String

    public init(id: String, name: String, detail: String, spriteID: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.spriteID = spriteID
    }
}

/// One stretch of the daily journey: `[startMeters, endMeters)`.
public struct Zone: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var tagline: String
    public var detail: String
    public var biome: Biome
    public var startMeters: Int
    public var endMeters: Int
    public var discovery: Collectible?

    public init(id: String, name: String, tagline: String, detail: String, biome: Biome,
                startMeters: Int, endMeters: Int, discovery: Collectible? = nil) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.detail = detail
        self.biome = biome
        self.startMeters = startMeters
        self.endMeters = endMeters
        self.discovery = discovery
    }

    public var lengthMeters: Int { endMeters - startMeters }

    public func contains(meters: Int) -> Bool { meters >= startMeters && meters < endMeters }
}
