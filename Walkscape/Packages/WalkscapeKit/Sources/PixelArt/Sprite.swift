import Foundation

/// Maps sprite characters to colours. `.` (and any unmapped key) is transparent.
public struct SpritePalette: Hashable, Sendable {
    public var colors: [Character: PixelColor]

    public init(_ colors: [Character: PixelColor]) {
        self.colors = colors
    }

    public subscript(key: Character) -> PixelColor? {
        key == "." ? nil : colors[key]
    }

    /// A copy with some keys replaced (used for character colour variants).
    public func overriding(_ overrides: [Character: PixelColor]) -> SpritePalette {
        SpritePalette(colors.merging(overrides) { _, new in new })
    }
}

/// A hand-authored sprite: rows of palette keys. This text format is the
/// placeholder art pipeline — see `Walkscape/docs/ART_PIPELINE.md` for how
/// to replace sprites with PNG files from an artist.
public struct Sprite: Hashable, Sendable {
    public let name: String
    public let rows: [[Character]]
    public let palette: SpritePalette

    public var width: Int { rows.map(\.count).max() ?? 0 }
    public var height: Int { rows.count }

    public init(name: String, palette: SpritePalette, rows: [String]) {
        self.name = name
        self.palette = palette
        let width = rows.map(\.count).max() ?? 0
        // Pad short rows so every sprite is rectangular.
        self.rows = rows.map { Array($0) + Array(repeating: ".", count: width - $0.count) }
    }

    /// Multi-line string form; blank lines and leading/trailing whitespace are ignored.
    public init(name: String, palette: SpritePalette, art: String) {
        let rows = art.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.init(name: name, palette: palette, rows: rows)
    }

    public func render(palette: SpritePalette? = nil, flipped: Bool = false) -> PixelCanvas {
        var canvas = PixelCanvas(width: width, height: height)
        canvas.draw(self, x: 0, y: 0, palette: palette, flipped: flipped)
        return canvas
    }
}
