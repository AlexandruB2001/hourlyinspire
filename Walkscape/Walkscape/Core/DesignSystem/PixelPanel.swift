import SwiftUI

/// The standard card: dark forest surface, crisp ink outline and a one-point
/// top highlight that gives a subtle bevelled pixel look.
struct PixelPanel: ViewModifier {
    var fill: Color = Theme.Palette.forestDeep
    var padding: CGFloat = Theme.Spacing.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(fill)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, Theme.Radius.m)
                            .padding(.top, 2)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .strokeBorder(Theme.Palette.ink, lineWidth: 2)
            }
    }
}

extension View {
    func pixelPanel(fill: Color = Theme.Palette.forestDeep, padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(PixelPanel(fill: fill, padding: padding))
    }
}

/// Small uppercase label used above sections and inside cards.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.Palette.creamDim

    init(_ text: String, color: Color = Theme.Palette.creamDim) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.eyebrow)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// Section header with an optional trailing action.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.cream)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
