import Foundation

/// An sRGB colour with straight (non-premultiplied) alpha.
public struct PixelColor: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `PixelColor(0x2F5D46)`.
    public init(_ hex: UInt32, alpha: UInt8 = 255) {
        self.init(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF), a: alpha)
    }

    public static let clear = PixelColor(r: 0, g: 0, b: 0, a: 0)

    public func withAlpha(_ alpha: UInt8) -> PixelColor {
        PixelColor(r: r, g: g, b: b, a: alpha)
    }

    /// Linear mix toward `other` by `t` (0...1).
    public func mixed(with other: PixelColor, _ t: Double) -> PixelColor {
        let t = min(1, max(0, t))
        func lerp(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return PixelColor(r: lerp(r, other.r), g: lerp(g, other.g), b: lerp(b, other.b), a: lerp(a, other.a))
    }
}

/// A small RGBA bitmap that pixel art is drawn into. Rendering is pure Swift
/// so scenes can be generated (and tested) on any platform; the app turns
/// canvases into `CGImage`s and scales them up with nearest-neighbour.
public struct PixelCanvas: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [PixelColor]
    /// When true, x coordinates wrap so the canvas tiles horizontally.
    public var wrapsHorizontally: Bool

    public init(width: Int, height: Int, fill: PixelColor = .clear, wrapsHorizontally: Bool = false) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.pixels = Array(repeating: fill, count: self.width * self.height)
        self.wrapsHorizontally = wrapsHorizontally
    }

    public subscript(x: Int, y: Int) -> PixelColor {
        guard let index = index(x, y) else { return .clear }
        return pixels[index]
    }

    private func index(_ x: Int, _ y: Int) -> Int? {
        guard y >= 0, y < height else { return nil }
        var x = x
        if wrapsHorizontally {
            x = ((x % width) + width) % width
        } else if x < 0 || x >= width {
            return nil
        }
        return y * width + x
    }

    /// Draws one pixel, alpha-blending over what is there.
    public mutating func plot(_ x: Int, _ y: Int, _ color: PixelColor) {
        guard color.a > 0, let index = index(x, y) else { return }
        if color.a == 255 {
            pixels[index] = color
            return
        }
        let dst = pixels[index]
        let sa = Double(color.a) / 255
        let da = Double(dst.a) / 255
        let outA = sa + da * (1 - sa)
        guard outA > 0 else { return }
        func channel(_ s: UInt8, _ d: UInt8) -> UInt8 {
            UInt8(((Double(s) * sa + Double(d) * da * (1 - sa)) / outA).rounded())
        }
        pixels[index] = PixelColor(r: channel(color.r, dst.r), g: channel(color.g, dst.g), b: channel(color.b, dst.b),
                                   a: UInt8((outA * 255).rounded()))
    }

    /// Replaces every pixel with `transform(pixel, x, y)` (no blending).
    public mutating func recolor(_ transform: (PixelColor, Int, Int) -> PixelColor) {
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                pixels[index] = transform(pixels[index], x, y)
            }
        }
    }

    public mutating func fillRect(x: Int, y: Int, width: Int, height: Int, _ color: PixelColor) {
        guard width > 0, height > 0 else { return }
        for yy in y..<(y + height) {
            for xx in x..<(x + width) { plot(xx, yy, color) }
        }
    }

    public mutating func hline(x: Int, y: Int, length: Int, _ color: PixelColor) {
        fillRect(x: x, y: y, width: length, height: 1, color)
    }

    public mutating func vline(x: Int, y: Int, length: Int, _ color: PixelColor) {
        fillRect(x: x, y: y, width: 1, height: length, color)
    }

    /// Fills each column from `top(x)` down to `bottom` (exclusive).
    public mutating func fillColumns(bottom: Int, _ color: PixelColor, top: (Int) -> Int) {
        for x in 0..<width {
            let start = max(0, top(x))
            if start < bottom { vline(x: x, y: start, length: bottom - start, color) }
        }
    }

    public mutating func fillEllipse(cx: Int, cy: Int, rx: Int, ry: Int, _ color: PixelColor) {
        guard rx >= 0, ry >= 0 else { return }
        let rx2 = Double(rx) + 0.5
        let ry2 = Double(ry) + 0.5
        for dy in -ry...ry {
            for dx in -rx...rx {
                let nx = Double(dx) / rx2
                let ny = Double(dy) / ry2
                if nx * nx + ny * ny <= 1 { plot(cx + dx, cy + dy, color) }
            }
        }
    }

    /// Draws `other` on top of this canvas with its top-left at (x, y).
    public mutating func draw(_ other: PixelCanvas, x: Int, y: Int) {
        for yy in 0..<other.height {
            for xx in 0..<other.width { plot(x + xx, y + yy, other[xx, yy]) }
        }
    }

    public mutating func draw(_ sprite: Sprite, x: Int, y: Int, palette: SpritePalette? = nil, flipped: Bool = false) {
        let palette = palette ?? sprite.palette
        for (row, line) in sprite.rows.enumerated() {
            for (column, key) in line.enumerated() {
                guard let color = palette[key] else { continue }
                let drawX = flipped ? x + sprite.width - 1 - column : x + column
                plot(drawX, y + row, color)
            }
        }
    }

    /// Straight-alpha RGBA bytes, row-major, top row first.
    public var rgbaBytes: [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(pixels.count * 4)
        for pixel in pixels { bytes += [pixel.r, pixel.g, pixel.b, pixel.a] }
        return bytes
    }

    /// Returns a canvas `factor` times larger (nearest neighbour).
    public func scaled(by factor: Int) -> PixelCanvas {
        let factor = max(1, factor)
        var result = PixelCanvas(width: width * factor, height: height * factor)
        for y in 0..<result.height {
            for x in 0..<result.width {
                result.pixels[y * result.width + x] = pixels[(y / factor) * width + x / factor]
            }
        }
        return result
    }
}
