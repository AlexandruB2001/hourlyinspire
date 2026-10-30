import PixelArt
import SwiftUI
import UIKit
import WalkscapeDomain

/// What a shareable card says. Built from the model at the moment you tap
/// Share, so it captures progress "as of now".
struct MilestoneCardContent: Identifiable, Hashable {
    struct Stat: Hashable {
        let value: String
        let label: String
    }

    let id: String
    let eyebrow: String
    let title: String
    let detail: String
    let day: LocalDay
    let iconID: String?
    let biome: Biome
    let stats: [Stat]
    // The walker as they look today.
    let avatarID: String
    let outfit: [String]
    let companionID: String?
    let companionKilometres: Int

    @MainActor
    static func currentProgress(_ model: AppModel) -> MilestoneCardContent {
        let zone = model.zoneProgress.currentZone
        var stats = [Stat(value: DistanceFormatting.kilometres(model.distanceMeters), label: "today"),
                     Stat(value: DistanceFormatting.kilometres(model.progression.lifetimeMeters), label: "all time"),
                     Stat(value: "\(model.progression.discoveredZoneIDs.count)", label: "zones found")]
        if let growth = model.companionGrowth { stats.append(Stat(value: growth.stage.name, label: "companion")) }
        return MilestoneCardContent(id: "progress-\(Date().timeIntervalSince1970)", eyebrow: "My journey today",
                                    title: zone.name, detail: zone.tagline, day: model.today, iconID: nil,
                                    biome: zone.biome, stats: stats, model: model)
    }

    @MainActor
    static func journal(_ entry: JournalEntry, model: AppModel) -> MilestoneCardContent {
        let eyebrow: String
        switch entry.kind {
        case .distance: eyebrow = "Distance milestone"
        case .zone: eyebrow = "New zone"
        case .relic: eyebrow = "Relic discovered"
        case .achievement: eyebrow = "Achievement"
        case .companion: eyebrow = "Companion"
        case .referral: eyebrow = "Invite reward"
        case .team: eyebrow = "Team milestone"
        case .expedition: eyebrow = "Expedition complete"
        case .level: eyebrow = "Explorer level"
        }
        // Zone entries show that zone; everything else shows where you are now.
        let parts = entry.iconID.split(separator: ":").map(String.init)
        let biome = parts.first == "zone" ? parts.last.flatMap(Biome.init(rawValue:)) : nil
        return MilestoneCardContent(id: "journal-\(entry.id)", eyebrow: eyebrow, title: entry.title, detail: entry.detail,
                                    day: entry.day, iconID: biome == nil ? entry.iconID : nil,
                                    biome: biome ?? model.zoneProgress.currentZone.biome,
                                    stats: [Stat(value: DistanceFormatting.kilometres(model.progression.lifetimeMeters),
                                                 label: "walked in total")],
                                    model: model)
    }

    @MainActor
    private init(id: String, eyebrow: String, title: String, detail: String, day: LocalDay, iconID: String?,
                 biome: Biome, stats: [Stat], model: AppModel) {
        self.id = id
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.day = day
        self.iconID = iconID
        self.biome = biome
        self.stats = stats
        avatarID = model.settings.avatarID
        outfit = model.outfit
        companionID = model.companion?.speciesID
        companionKilometres = model.companionGrowth?.kilometres ?? 0
    }
}

/// The card itself, drawn at a fixed size so it renders identically on every device.
struct MilestoneCardView: View {
    let content: MilestoneCardContent
    static let size = CGSize(width: 360, height: 500)

    var body: some View {
        VStack(spacing: 0) {
            PixelSceneView(biome: content.biome, avatarID: content.avatarID, outfit: content.outfit,
                           companionImage: content.companionID.flatMap {
                               PixelArtCache.shared.companion($0, kilometres: content.companionKilometres)
                           },
                           walking: false, pixel: 3, characterPosition: 0.42, animated: false)
                .frame(height: 230)
                .overlay(alignment: .topLeading) {
                    if let iconID = content.iconID {
                        JournalIcon(iconID: iconID, size: 52)
                            .padding(Theme.Spacing.m)
                    }
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.Palette.forestDeep], startPoint: .top, endPoint: .bottom)
                        .frame(height: 50)
                }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Eyebrow(content.eyebrow, color: Theme.Palette.gold)
                Text(content.title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(content.detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .lineLimit(3)
                HStack(alignment: .top, spacing: Theme.Spacing.l) {
                    ForEach(content.stats, id: \.self) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.value)
                                .font(Theme.Typography.stat)
                                .foregroundStyle(Theme.Palette.cream)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(stat.label)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.creamDim)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                Spacer(minLength: 0)
                HStack {
                    Text(content.day.displayDate)
                    Spacer()
                    ItemIcon(spriteID: "boot", pixel: 1.6)
                    Text("Walkscape: Journey")
                }
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Palette.forestDeep)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.Palette.forestDeep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).strokeBorder(Theme.Palette.ink, lineWidth: 4))
        .environment(\.colorScheme, .dark)
    }
}

/// Previews a card and hands it to the system share sheet (which also offers "Save Image").
struct ShareCardSheet: View {
    let content: MilestoneCardContent
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                if let rendered {
                    Image(uiImage: rendered)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 420)
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    let image = Image(uiImage: rendered)
                    ShareLink(item: image, preview: SharePreview(content.title, image: image)) {
                        Label("Share or save image", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.pixel)
                } else {
                    ProgressView().tint(Theme.Palette.gold)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { render() }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: MilestoneCardView(content: content))
        renderer.scale = 3
        rendered = renderer.uiImage
    }
}
