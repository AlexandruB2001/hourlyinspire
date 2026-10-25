import SwiftUI
import WalkscapeDomain

/// Today's route as a row of zone postcards: passed, current and ahead.
struct TrailStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.zoneProgress.zoneIndex
        // Always show the defined journey, plus any extra zones walked today.
        let count = max(model.engine.catalog.zones.count, current + 2)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Today's trail") {
                Text("\(current) of \(model.engine.catalog.zones.count) km milestones")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(0..<count, id: \.self) { index in
                            TrailStop(zone: model.engine.catalog.zone(at: index),
                                      state: index < current ? .passed : (index == current ? .current : .ahead))
                                .id(index)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .onAppear { reader.scrollTo(current, anchor: .center) }
                .onChange(of: current) { _, newValue in
                    withAnimation(.easeInOut) { reader.scrollTo(newValue, anchor: .center) }
                }
            }
        }
        .pixelPanel()
    }
}

private struct TrailStop: View {
    enum StopState { case passed, current, ahead }
    let zone: Zone
    let state: StopState

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            PixelImageView(image: PixelArtCache.shared.thumbnail(zone.biome, width: 48, height: 28), pixel: 1.5)
                .saturation(state == .ahead ? 0.25 : 1)
                .brightness(state == .ahead ? -0.15 : 0)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .strokeBorder(state == .current ? Theme.Palette.gold : Theme.Palette.ink,
                                      lineWidth: state == .current ? 3 : 2)
                }
                .overlay(alignment: .topTrailing) { badge.padding(3) }
            Text(zone.name)
                .font(Theme.Typography.micro)
                .foregroundStyle(state == .ahead ? Theme.Palette.creamDim : Theme.Palette.cream)
                .lineLimit(1)
            Text("km \(zone.startMeters / 1_000)")
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.leaf, Theme.Palette.ink)
        case .current:
            Image(systemName: "figure.walk.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.ink, Theme.Palette.gold)
        case .ahead:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        switch state {
        case .passed: return "\(zone.name), passed"
        case .current: return "\(zone.name), you are here"
        case .ahead: return "\(zone.name), starts at kilometre \(zone.startMeters / 1_000)"
        }
    }
}

/// A preview of where the next kilometre leads.
struct NextZoneCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.zoneProgress
        let next = progress.nextZone
        let item = next.discovery
        let found = item.map { model.progression.collectedItemIDs.contains($0.id) } ?? false
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Eyebrow("Next destination")
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                PixelImageView(image: PixelArtCache.shared.thumbnail(next.biome, width: 60, height: 44), pixel: 2)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(next.name)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.cream)
                    Text(next.tagline)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Label(DistanceFormatting.remaining(progress.metersToNextZone) + " away", systemImage: "flag.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            if let item {
                HStack(spacing: Theme.Spacing.s) {
                    ItemIcon(spriteID: item.spriteID, pixel: 2, locked: !found)
                    Text(found ? "You've found the \(item.name) here before." : "A discovery is waiting here…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            }
        }
        .pixelPanel()
        .accessibilityElement(children: .combine)
    }
}
