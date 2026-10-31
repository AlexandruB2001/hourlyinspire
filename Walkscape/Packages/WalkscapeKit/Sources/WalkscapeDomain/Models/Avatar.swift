import Foundation

/// A starter character look. The pixel-art layer maps `id` to palettes.
public struct AvatarStyle: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum AvatarCatalog {
    public static let starters: [AvatarStyle] = [
        AvatarStyle(id: "fern", name: "Fern"),
        AvatarStyle(id: "sky", name: "Sky"),
        AvatarStyle(id: "ember", name: "Ember"),
        AvatarStyle(id: "plum", name: "Plum"),
        AvatarStyle(id: "sunny", name: "Sunny"),
        AvatarStyle(id: "frost", name: "Frost"),
    ]

    public static let defaultID = "fern"
}

/// Hairstyles for the walker.
public enum HairStyle: String, CaseIterable, Identifiable, Sendable {
    case short, pigtails, long, bun, spiky

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .short: return "Short"
        case .pigtails: return "Pigtails"
        case .long: return "Long"
        case .bun: return "Bun"
        case .spiky: return "Spiky"
        }
    }
}

/// What the walker wears below the tunic: a slightly different silhouette.
public enum BodyStyle: String, CaseIterable, Identifiable, Sendable {
    case trousers, shorts, dress

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .trousers: return "Trousers"
        case .shorts: return "Shorts"
        case .dress: return "Dress"
        }
    }
}

/// Skin tones, lightest to deepest. Nil keeps the colour set's own tone.
public enum SkinTone: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, two, three, four, five

    public var id: Int { rawValue }
}

/// The walker's full look, packed into the avatar id that's stored and shared
/// with friends: "<colours>[-<hair>][-<body>][-skin<n>]", e.g.
/// "fern-pigtails-dress-skin3". Defaults are left out, so plain looks keep
/// their old ids, and older app versions simply draw the colours.
public struct CharacterLook: Hashable, Sendable {
    public var colors: String
    public var hair: HairStyle
    public var body: BodyStyle
    public var skin: SkinTone?

    public init(colors: String = AvatarCatalog.defaultID, hair: HairStyle = .short, body: BodyStyle = .trousers,
                skin: SkinTone? = nil) {
        self.colors = colors
        self.hair = hair
        self.body = body
        self.skin = skin
    }

    /// Reads an avatar id; unknown parts are ignored.
    public init(avatarID: String) {
        let parts = avatarID.split(separator: "-").map(String.init)
        let first = parts.first ?? AvatarCatalog.defaultID
        colors = AvatarCatalog.starters.contains { $0.id == first } ? first : AvatarCatalog.defaultID
        hair = .short
        body = .trousers
        skin = nil
        for part in parts.dropFirst() {
            if let style = HairStyle(rawValue: part) { hair = style }
            else if let style = BodyStyle(rawValue: part) { body = style }
            else if part.hasPrefix("skin"), let tone = Int(part.dropFirst(4)).flatMap(SkinTone.init(rawValue:)) { skin = tone }
        }
    }

    public func with(colors: String) -> CharacterLook { var look = self; look.colors = colors; return look }
    public func with(hair: HairStyle) -> CharacterLook { var look = self; look.hair = hair; return look }
    public func with(body: BodyStyle) -> CharacterLook { var look = self; look.body = body; return look }
    public func with(skin: SkinTone?) -> CharacterLook { var look = self; look.skin = skin; return look }

    public var avatarID: String {
        var parts = [colors]
        if hair != .short { parts.append(hair.rawValue) }
        if body != .trousers { parts.append(body.rawValue) }
        if let skin { parts.append("skin\(skin.rawValue)") }
        return parts.joined(separator: "-")
    }
}
