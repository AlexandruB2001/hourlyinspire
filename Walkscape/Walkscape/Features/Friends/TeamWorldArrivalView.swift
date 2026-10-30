import PixelArt
import SwiftUI
import WalkscapeDomain

/// A team-world zone the team just reached.
struct TeamWorldArrival: Identifiable, Equatable {
    let zone: TeamWorldZone
    let world: TeamWorld
    let teamName: String

    var id: String { zone.id }
}

/// Full-screen moment when the team reaches a new zone: the new land fades in,
/// the walker strolls in, then the relic and rewards pop up.
struct TeamWorldArrivalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let arrival: TeamWorldArrival
    @State private var stage = 0
    @State private var hop = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            PixelSceneView(biome: arrival.zone.biome, avatarID: model.settings.avatarID, outfit: model.outfit, walking: true,
                           characterPosition: stage >= 1 ? 0.4 : 0.05, tint: arrival.world.tint)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.ink, lineWidth: 3))
                .opacity(stage >= 1 ? 1 : 0)
                .scaleEffect(stage >= 1 ? 1 : 1.08)
            VStack(spacing: Theme.Spacing.s) {
                Eyebrow(arrival.world.name, color: Theme.Palette.gold)
                Text("\(arrival.teamName) reached")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Text(arrival.zone.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                Text(arrival.zone.tagline)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .multilineTextAlignment(.center)
            }
            .opacity(stage >= 2 ? 1 : 0)
            .offset(y: stage >= 2 ? 0 : 12)
            HStack(spacing: Theme.Spacing.m) {
                ItemIcon(spriteID: arrival.zone.relic.spriteID, pixel: 5)
                    .offset(y: hop ? -6 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("Relic found", color: Theme.Palette.gold)
                    Text(arrival.zone.relic.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    Text("+\(arrival.zone.reward.coins) coins · +\(arrival.zone.reward.xp) XP")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
                Spacer(minLength: 0)
            }
            .pixelPanel(fill: Theme.Palette.forestRaised, padding: Theme.Spacing.m)
            .opacity(stage >= 3 ? 1 : 0)
            .scaleEffect(stage >= 3 ? 1 : 0.85)
            Spacer(minLength: 0)
            Button("Onward!") { dismiss() }
                .buttonStyle(.pixel)
                .opacity(stage >= 3 ? 1 : 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.night.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: stage == 3)
        .task {
            withAnimation(.easeOut(duration: 1.2)) { stage = 1 }
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.5)) { stage = 2 }
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { stage = 3 }
            withAnimation(.easeInOut(duration: 0.4).repeatCount(5, autoreverses: true)) { hop = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(arrival.teamName) reached \(arrival.zone.name) in \(arrival.world.name). Found the \(arrival.zone.relic.name).")
    }
}

/// A world's creatures, treasure and quests, for the world map.
struct WorldDetails: View {
    @Environment(AppModel.self) private var model
    let world: TeamWorld
    let progress: TeamWorldProgress

    var body: some View {
        let seen = Set(model.collections.wildlife.keys)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Eyebrow("Wildlife")
            HStack(spacing: Theme.Spacing.m) {
                ForEach(world.creatures) { creature in
                    let spotted = seen.contains(creature.id)
                    VStack(spacing: 2) {
                        ItemIcon(spriteID: creature.spriteID, pixel: 2.6)
                            .colorMultiply(spotted ? .white : .black)
                            .opacity(spotted ? 1 : 0.45)
                        Text(spotted ? creature.name : "???")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(spotted ? Theme.Palette.cream : Theme.Palette.creamDim)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(creature.rarity.displayName)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spotted ? "\(creature.name), spotted" : "Unknown \(creature.rarity.displayName) creature")
                }
            }
            Eyebrow("World quests")
            let quests = world.quests(progress: progress, seenCreatures: seen,
                                      challengeDone: model.ledger.hasClaimed(world.challengeReward.id))
            ForEach(quests) { quest in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: quest.isComplete ? "checkmark.seal.fill" : "circle")
                        .foregroundStyle(quest.isComplete ? Theme.Palette.gold : Theme.Palette.creamDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quest.name)
                            .font(Theme.Typography.caption.weight(.heavy))
                            .foregroundStyle(Theme.Palette.cream)
                        Text(quest.detail)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                        if let treasure = quest.treasure {
                            Text("Reward: the \(treasure.name)")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.gold)
                        }
                    }
                    Spacer(minLength: 0)
                    if quest.goal > 1 {
                        Text("\(min(quest.done, quest.goal))/\(quest.goal)")
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let title = TeamWorldContent.titles[world.id] {
                Text("Explore every zone to earn the title \u{201C}\(title)\u{201D}.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
    }
}
