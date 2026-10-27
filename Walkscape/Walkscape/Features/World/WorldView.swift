import SwiftUI
import WalkscapeDomain

/// The whole journey: every zone, what's been discovered, and lifetime progress.
struct WorldView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    LifetimeHeader()
                        .padding(.bottom, Theme.Spacing.l)
                    let zones = model.engine.catalog.zones
                    ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                        ZoneCard(zone: zone, index: index)
                        if index < zones.count - 1 { TrailConnector() }
                    }
                    if model.progression.bestDayMeters >= model.engine.catalog.definedEndMeters {
                        TrailConnector()
                        BeyondCard()
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("World")
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
        }
    }
}

private struct LifetimeHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progression = model.progression
        let total = model.engine.catalog.zones.count
        let discovered = model.engine.catalog.zones.filter { progression.discoveredZoneIDs.contains($0.id) }.count
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Eyebrow("Your journey so far")
            HStack {
                StatBlock(value: DistanceFormatting.kilometres(progression.lifetimeMeters), label: "lifetime")
                Spacer()
                StatBlock(value: "\(discovered)/\(total)", label: "zones discovered", alignment: .center)
                Spacer()
                StatBlock(value: DistanceFormatting.kilometres(progression.bestDayMeters), label: "best day", alignment: .trailing)
            }
            PixelProgressBar(fraction: Double(discovered) / Double(max(1, total)), segments: total, fill: Theme.Palette.leaf)
            if model.isDemo {
                Text("Demo progress is kept separate from your Apple Health journey.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.crystal)
            }
        }
        .pixelPanel()
    }
}

private struct ZoneCard: View {
    @Environment(AppModel.self) private var model
    let zone: Zone
    let index: Int

    var body: some View {
        let discovered = model.progression.discoveredZoneIDs.contains(zone.id)
        let isHereToday = model.zoneProgress.zoneIndex == index
        let reachedToday = model.zoneProgress.zoneIndex >= index
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ZStack(alignment: .topLeading) {
                PixelSceneView(biome: zone.biome, avatarID: isHereToday ? model.settings.avatarID : nil,
                               walking: isHereToday && model.distanceMeters > 0, pixel: 2.5, characterPosition: 0.4,
                               animated: isHereToday)
                    .frame(height: 120)
                    .saturation(discovered ? 1 : 0)
                    .brightness(discovered ? 0 : -0.25)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .strokeBorder(isHereToday ? Theme.Palette.gold : Theme.Palette.ink, lineWidth: isHereToday ? 3 : 2))
                HStack {
                    StatusChip(text: "km \(zone.startMeters / 1_000)–\(zone.endMeters / 1_000)")
                    Spacer()
                    if isHereToday {
                        StatusChip(text: "You are here today", systemImage: "figure.walk", tint: Theme.Palette.gold)
                    } else if !discovered {
                        StatusChip(text: "Undiscovered", systemImage: "lock.fill")
                    } else if reachedToday {
                        StatusChip(text: "Passed today", systemImage: "checkmark", tint: Theme.Palette.leaf)
                    }
                }
                .padding(Theme.Spacing.s)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(discovered ? zone.name : "???")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                Text(discovered ? zone.detail : "Walk \(zone.startMeters / 1_000) km in a single day to discover this place.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let item = zone.discovery {
                let found = model.progression.collectedItemIDs.contains(item.id)
                HStack(spacing: Theme.Spacing.m) {
                    ItemIcon(spriteID: item.spriteID, pixel: 3, locked: !found)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(found ? item.name : "Hidden discovery")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(found ? Theme.Palette.gold : Theme.Palette.creamDim)
                        Text(found ? item.detail : "Found the first time you reach this zone.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
                .padding(Theme.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
            }
        }
        .pixelPanel()
        .accessibilityElement(children: .combine)
    }
}

private struct BeyondCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Eyebrow("Beyond the map", color: Theme.Palette.gold)
            Text("Wanderer's Road")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.cream)
            Text("Past the lighthouse the road keeps going. Your best day reached \(DistanceFormatting.kilometres(model.progression.bestDayMeters)).")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .pixelPanel()
    }
}

/// Dotted path joining the zone cards.
private struct TrailConnector: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().fill(Theme.Palette.bark).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityHidden(true)
    }
}
