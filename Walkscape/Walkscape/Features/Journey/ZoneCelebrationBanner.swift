import SwiftUI
import WalkscapeDomain

/// Shown once when the walker reaches a new zone. Several boundaries crossed
/// in one update arrive as a single banner.
struct ZoneCelebrationBanner: View {
    let celebration: ZoneCelebration
    let dismiss: () -> Void

    @State private var sparkle = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PixelImageView(image: PixelArtCache.shared.thumbnail(celebration.zone.biome, width: 40, height: 30), pixel: 1.5)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.gold, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(celebration.boundariesCrossed > 1 ? "\(celebration.boundariesCrossed) new zones!" : "New zone reached",
                        color: Theme.Palette.gold)
                Text(celebration.zone.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                if let item = celebration.newDiscoveries.last {
                    HStack(spacing: Theme.Spacing.xs) {
                        ItemIcon(spriteID: item.spriteID, pixel: 1.6)
                        Text(celebration.newDiscoveries.count > 1
                             ? "Found \(item.name) +\(celebration.newDiscoveries.count - 1) more"
                             : "Found: \(item.name)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Theme.Palette.gold)
                .scaleEffect(sparkle ? 1.15 : 0.85)
                .opacity(sparkle ? 1 : 0.6)
        }
        .pixelPanel(fill: Theme.Palette.forestRaised, padding: Theme.Spacing.m)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .onTapGesture(perform: dismiss)
        .sensoryFeedback(.success, trigger: celebration)
        .task {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { sparkle = true }
            try? await Task.sleep(for: .seconds(5))
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismiss")
    }
}
