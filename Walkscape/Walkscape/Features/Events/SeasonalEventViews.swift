import SwiftUI
import WalkscapeDomain

/// The running seasonal event on the Journey screen.
struct SeasonalEventCard: View {
    @Environment(AppModel.self) private var model
    let run: EventRun
    @State private var open = false

    var body: some View {
        let progress = model.eventProgress(run)
        Button { open = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                ItemIcon(spriteID: run.event.spriteID, pixel: 4)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Eyebrow("Festival · \(run.daysLeft(from: model.today)) days left", color: Theme.Palette.gold)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.creamDim)
                    }
                    Text(run.event.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    Text(run.event.tagline)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                    TierTrack(run: run, progress: progress)
                }
            }
            .pixelPanel(fill: Theme.Palette.forestRaised)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(run.event.name), \(progress.tiersReached) of \(run.event.tiers.count) tiers, \(run.daysLeft(from: model.today)) days left")
        .sheet(isPresented: $open) { SeasonalEventSheet(run: run) }
    }
}

/// Tier markers along the event distance.
private struct TierTrack: View {
    let run: EventRun
    let progress: EventProgress

    var body: some View {
        let goal = run.event.tiers.last?.kilometres ?? 1
        VStack(alignment: .leading, spacing: 2) {
            PixelProgressBar(fraction: Double(progress.kilometres) / Double(goal), segments: 16, fill: Theme.Palette.gold, height: 10)
            HStack(spacing: 0) {
                ForEach(Array(run.event.tiers.enumerated()), id: \.offset) { index, tier in
                    Text("\(tier.kilometres) km")
                        .font(.system(size: 9, weight: index < progress.tiersReached ? .heavy : .regular, design: .rounded))
                        .foregroundStyle(index < progress.tiersReached ? Theme.Palette.gold : Theme.Palette.creamDim)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Text("\(progress.kilometres) km walked in the festival")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
        }
    }
}

/// Everything about one festival: tiers, quests and the community goal.
struct SeasonalEventSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let run: EventRun

    var body: some View {
        let progress = model.eventProgress(run)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Eyebrow("\(run.startDay.displayDate) – \(run.endDay.displayDate) · every year", color: Theme.Palette.gold)
                        Text(run.event.tagline)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.cream)
                        Text("\(run.daysLeft(from: model.today)) days left. Days count up to 10 km each, so steady walks win.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                    tiers(progress)
                    quests(progress)
                    community(progress)
                    Text("Missed something? Festivals return every year, and their exclusive items join the shop once the festival ends.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle(run.event.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func tiers(_ progress: EventProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Festival tiers").font(Theme.Typography.headline).foregroundStyle(Theme.Palette.cream)
            TierTrack(run: run, progress: progress)
            ForEach(Array(run.event.tiers.enumerated()), id: \.offset) { index, tier in
                let reached = index < progress.tiersReached
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: reached ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(reached ? Theme.Palette.gold : Theme.Palette.creamDim)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tier \(index + 1) · \(tier.kilometres) km")
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundStyle(reached ? Theme.Palette.cream : Theme.Palette.creamDim)
                        Text(rewardText(tier, last: index == run.event.tiers.count - 1))
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.gold.opacity(reached ? 1 : 0.7))
                    }
                    Spacer()
                    if let item = tier.itemIDs.first, let companion = model.companion {
                        PixelImageView(image: PixelArtCache.shared.companion(companion.speciesID,
                                                                            kilometres: model.companionGrowth?.kilometres ?? 0,
                                                                            accessories: [item]), pixel: 2)
                    }
                }
            }
        }
        .pixelPanel()
    }

    private func rewardText(_ tier: SeasonalEvent.Tier, last: Bool) -> String {
        var parts = ["+\(tier.coins) coins", "+\(tier.xp) XP"]
        for id in tier.itemIDs {
            if let accessory = CompanionAccessoryCatalog.accessory(withID: id) { parts.append(accessory.name) }
        }
        if last, let title = TitleCatalog.title(withID: run.event.titleID) { parts.append("title \u{201C}\(title.name)\u{201D}") }
        return parts.joined(separator: " · ")
    }

    private func quests(_ progress: EventProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Festival quests").font(Theme.Typography.headline).foregroundStyle(Theme.Palette.cream)
            ForEach(run.event.quests) { quest in
                let value = progress.progress(of: quest)
                let done = value >= quest.target
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(quest.title)
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundStyle(done ? Theme.Palette.creamDim : Theme.Palette.cream)
                            .strikethrough(done)
                        Spacer()
                        Text("\(value)/\(quest.target)")
                            .font(Theme.Typography.micro.monospacedDigit())
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                    PixelProgressBar(fraction: Double(value) / Double(quest.target), segments: 12,
                                     fill: done ? Theme.Palette.leaf : Theme.Palette.gold, height: 8)
                    Text("+\(quest.coins) coins · +\(quest.xp) XP")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
        }
        .pixelPanel()
    }

    private func community(_ progress: EventProgress) -> some View {
        let goal = run.event.communityGoalKilometres
        let km = (model.communityMeters[run.id] ?? 0) / 1_000
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Community goal").font(Theme.Typography.headline).foregroundStyle(Theme.Palette.cream)
            Text("Every Walkscape walker together: \(goal.formatted()) km. Walk 5 km in the festival to share the reward.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            PixelProgressBar(fraction: Double(km) / Double(goal), segments: 16, fill: Theme.Palette.leaf)
            Text(model.isSignedIn ? "\(km.formatted()) km so far" : "Sign in (Social tab) to see the community total.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .pixelPanel()
    }
}
