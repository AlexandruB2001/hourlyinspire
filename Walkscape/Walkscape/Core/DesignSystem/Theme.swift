import SwiftUI

/// Walkscape design tokens. Views use these instead of literal values so the
/// look can be tuned in one place.
enum Theme {
    enum Palette {
        static let night = Color(hex: 0x141E1A)        // app background
        static let forestDeep = Color(hex: 0x1C2B25)   // panels
        static let forestRaised = Color(hex: 0x253830) // raised panels / rows
        static let forest = Color(hex: 0x2F5D46)
        static let moss = Color(hex: 0x4F8A5B)
        static let leaf = Color(hex: 0x7DBA5E)
        static let sky = Color(hex: 0x8DBEE0)
        static let skyMuted = Color(hex: 0x9CC3D5)
        static let cream = Color(hex: 0xF4EBD0)
        static let creamDim = Color(hex: 0xBFB79F)
        static let bark = Color(hex: 0x7A5638)
        static let gold = Color(hex: 0xE3B04B)
        static let goldDeep = Color(hex: 0xB9832E)
        static let ink = Color(hex: 0x0E1512)          // pixel outlines
        static let ember = Color(hex: 0xE07A5F)        // warnings
        static let crystal = Color(hex: 0x7FE0E8)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 4
        static let m: CGFloat = 8
        static let l: CGFloat = 14
    }

    /// One logical pixel of game art, in points. All scenes and sprites use
    /// integer multiples of this so pixels stay crisp.
    static let pixel: CGFloat = 3

    enum Typography {
        static let hero = Font.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit()
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let headline = Font.system(.headline, design: .rounded)
        static let body = Font.system(.body, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
        static let micro = Font.system(.caption2, design: .rounded).weight(.bold)
        static let stat = Font.system(.title3, design: .rounded).weight(.bold).monospacedDigit()
        /// Small caps-style label above sections, e.g. "NEXT DESTINATION".
        static let eyebrow = Font.system(.caption2, design: .rounded).weight(.heavy)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
