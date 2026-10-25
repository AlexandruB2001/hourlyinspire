import SwiftUI

/// Segmented, pixel-style progress bar.
struct PixelProgressBar: View {
    /// 0...1
    var fraction: Double
    var segments: Int = 20
    var fill: Color = Theme.Palette.gold
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let inner = geometry.size.width - 6
            let segmentWidth = max(1, (inner - gap * CGFloat(segments - 1)) / CGFloat(segments))
            let filled = fraction * Double(segments)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.ink)
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { index in
                        let amount = min(1, max(0, filled - Double(index)))
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.06))
                            Rectangle()
                                .fill(fill)
                                .frame(width: segmentWidth * amount)
                            Rectangle()
                                .fill(Color.white.opacity(amount > 0 ? 0.35 : 0))
                                .frame(width: segmentWidth * amount, height: 2)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .frame(width: segmentWidth)
                    }
                }
                .padding(3)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
    }
}

/// Chunky pill button with a drop "shadow" step, like a game UI button.
struct PixelButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let (fill, text, shadow): (Color, Color, Color) = {
            switch kind {
            case .primary: return (Theme.Palette.gold, Theme.Palette.ink, Theme.Palette.goldDeep)
            case .secondary: return (Theme.Palette.moss, Theme.Palette.cream, Theme.Palette.forest)
            case .quiet: return (Theme.Palette.forestRaised, Theme.Palette.cream, Theme.Palette.ink)
            }
        }()
        return configuration.label
            .font(Theme.Typography.caption)
            .foregroundStyle(text)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s + 2)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(shadow)
                    .offset(y: pressed ? 0 : 3)
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .strokeBorder(Theme.Palette.ink, lineWidth: 2)
            }
            .offset(y: pressed ? 3 : 0)
            .padding(.bottom, 3)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension ButtonStyle where Self == PixelButtonStyle {
    static var pixel: PixelButtonStyle { PixelButtonStyle(kind: .primary) }
    static var pixelSecondary: PixelButtonStyle { PixelButtonStyle(kind: .secondary) }
    static var pixelQuiet: PixelButtonStyle { PixelButtonStyle(kind: .quiet) }
}

/// Compact status chip ("Updated 2 min ago", "Demo data").
struct StatusChip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.Palette.cream

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text).lineLimit(1)
        }
        .font(Theme.Typography.micro)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(Theme.Palette.ink.opacity(0.72)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}

/// A labelled statistic, e.g. "3,180" over "steps".
struct StatBlock: View {
    let value: String
    let label: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(Theme.Typography.stat)
                .foregroundStyle(Theme.Palette.cream)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .accessibilityElement(children: .combine)
    }
}
