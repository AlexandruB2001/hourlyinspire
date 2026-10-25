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
