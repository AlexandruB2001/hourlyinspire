import PixelArt
import SwiftUI
import WalkscapeDomain

/// Team worlds: shared lands only a whole team can walk far enough to explore.
struct TeamWorldsCard: View {
    @Environment(AppModel.self) private var model
    let dashboard: TeamDashboard
    @State private var showsMap = false

    var body: some View {
        let progress = TeamWorldProgress(teamMeters: dashboard.team.totalMeters)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Eyebrow("Team worlds", color: Theme.Palette.gold)
                Spacer()
                if progress.isUnlocked {
                    Button("World map") { showsMap = true }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            if let world = progress.currentWorld {
                current(world, progress: progress)
            } else {
                locked(progress)
            }
        }
        .pixelPanel()
        .sheet(isPresented: $showsMap) { TeamWorldMap(progress: progress, teamName: dashboard.team.name) }
    }

    private func locked(_ progress: TeamWorldProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.Palette.creamDim)
                Text(TeamWorldCatalog.worlds.first?.name ?? "")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
            }
            Text("Finish the Summit Relay expedition together to open the first team world: lands too big for any one walker.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            PixelProgressBar(fraction: 1 - Double(progress.metersToUnlock) / Double(TeamWorldCatalog.startMeters(of: TeamWorldCatalog.worlds[0])),
                             segments: 14, fill: Theme.Palette.leaf)
            Text("\(DistanceFormatting.kilometres(progress.metersToUnlock)) to go as a team")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
        }
    }

    private func current(_ world: TeamWorld, progress: TeamWorldProgress) -> some View {
        let reached = progress.reachedZones(in: world)
        let here = reached.last ?? world.zones[0]
        let next = progress.nextZone(in: world)
        let walked = progress.meters(in: world)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            PixelSceneView(biome: here.biome, avatarID: model.settings.avatarID, outfit: model.outfit, walking: true,
                           characterPosition: 0.25, tint: world.tint)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.ink, lineWidth: 2))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(world.name)
                            .font(Theme.Typography.micro.weight(.heavy))
                            .foregroundStyle(Theme.Palette.gold)
                        Text(here.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Palette.cream)
                    }
                    .padding(Theme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.ink.opacity(0.65)))
                    .padding(Theme.Spacing.s)
                }
            Text(here.tagline)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            WorldTrail(world: world, reachedCount: reached.count)
            if let next {
                let span = next.metersFromWorldStart - here.metersFromWorldStart
                PixelProgressBar(fraction: Double(walked - here.metersFromWorldStart) / Double(max(1, span)), segments: 14,
                                 fill: Theme.Palette.gold)
                Text("\(DistanceFormatting.kilometres(next.metersFromWorldStart - walked)) as a team to \(next.name)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                challenge(world)
            }
            contributionNote
        }
    }

    private func challenge(_ world: TeamWorld) -> some View {
        let weekMeters = dashboard.members.compactMap(\.weekMeters).reduce(0, +)
        let done = model.ledger.hasClaimed(world.challengeReward.id)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(world.challenge.name)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.gold)
            Text(done ? "Completed! Your team woke the world." : world.challenge.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            if !done {
                PixelProgressBar(fraction: Double(weekMeters) / Double(world.challenge.weekMeters), segments: 14, fill: Theme.Palette.ember)
                Text("\(DistanceFormatting.kilometres(weekMeters)) of \(DistanceFormatting.kilometres(world.challenge.weekMeters)) this week")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised, padding: Theme.Spacing.m)
    }

    @ViewBuilder private var contributionNote: some View {
        let mine = model.myTeamContribution
        if mine < TeamWorldCatalog.minimumContribution {
            Text("Walk \(DistanceFormatting.kilometres(TeamWorldCatalog.minimumContribution - mine)) more for the team to collect world rewards.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.ember)
        } else {
            Text("You've walked \(DistanceFormatting.kilometres(mine)) for the team. Every zone you reach together lands in your Journal.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
        }
    }
}

/// Stepping stones for the zones of one world.
private struct WorldTrail: View {
    let world: TeamWorld
    let reachedCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(world.zones.enumerated()), id: \.element.id) { index, zone in
                let reached = index < reachedCount
                VStack(spacing: 2) {
                    ZStack {
                        Circle().fill(reached ? Theme.Palette.gold : Theme.Palette.forestRaised)
                        Circle().strokeBorder(Theme.Palette.ink, lineWidth: 2)
                        if reached {
                            ItemIcon(spriteID: zone.relic.spriteID, pixel: 1.6)
                        } else {
                            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Theme.Palette.creamDim)
                        }
                    }
                    .frame(width: 26, height: 26)
                    Text(zone.name)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(reached ? Theme.Palette.cream : Theme.Palette.creamDim)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                }
                if index < world.zones.count - 1 {
                    Rectangle()
                        .fill(index + 1 < reachedCount ? Theme.Palette.gold : Theme.Palette.ink)
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 26)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reachedCount) of \(world.zones.count) zones reached in \(world.name)")
    }
}

/// Every team world, its zones and relics.
private struct TeamWorldMap: View {
    let progress: TeamWorldProgress
    let teamName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    ForEach(TeamWorldCatalog.worlds) { world in
                        let reached = progress.reachedZones(in: world)
                        let open = progress.teamMeters >= TeamWorldCatalog.startMeters(of: world)
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            HStack {
                                Text(world.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(open ? Theme.Palette.cream : Theme.Palette.creamDim)
                                Spacer()
                                Text(open ? "\(reached.count)/\(world.zones.count)" : "Locked")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(open ? Theme.Palette.gold : Theme.Palette.creamDim)
                            }
                            Text(world.tagline)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.creamDim)
                            if open {
                                PixelImageView(image: PixelArtCache.shared.scene(world.zones[0].biome, width: 96, height: 30,
                                                                                 tint: world.tint)?.layers.composite().makeCGImage(),
                                               pixel: 3)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                                WorldTrail(world: world, reachedCount: reached.count)
                            } else {
                                Text("Opens after \(DistanceFormatting.kilometres(TeamWorldCatalog.startMeters(of: world))) of team walking.")
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Palette.creamDim)
                            }
                        }
                        .pixelPanel()
                    }
                    Text("\(teamName) has walked \(DistanceFormatting.kilometres(progress.teamMeters)) together.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("World map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
        }
    }
}
