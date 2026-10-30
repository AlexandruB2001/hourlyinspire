import SwiftUI
import WalkscapeDomain

/// Today's quests on the Journey screen, with a way into the full quest log.
struct QuestsCard: View {
    @Environment(AppModel.self) private var model
    @State private var showsAll = false

    var body: some View {
        let board = model.questBoard
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Today's quests") {
                Button {
                    showsAll = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if board.claimableCount > 0 {
                            Text("\(board.claimableCount)")
                                .font(Theme.Typography.micro.weight(.heavy))
                                .foregroundStyle(Theme.Palette.ink)
                                .padding(.horizontal, 5)
                                .background(Capsule().fill(Theme.Palette.gold))
                        }
                        Text("All quests")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
                }
                .accessibilityLabel(board.claimableCount > 0 ? "All quests, \(board.claimableCount) to claim" : "All quests")
            }
            if board.daily.isEmpty {
                Text("New quests arrive at midnight.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            ForEach(board.daily) { QuestRow(status: $0, compact: true) }
        }
        .pixelPanel()
        .sheet(isPresented: $showsAll) { QuestLogSheet() }
    }
}

/// Daily, weekly and companion quests, plus the weekly chest.
struct QuestLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chestReward: Reward?

    var body: some View {
        let board = model.questBoard
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    section("Daily", resets: "Resets at midnight", quests: board.daily)
                    section("Weekly", resets: "Resets Monday", quests: board.weekly)
                    WeeklyChestCard(board: board) { chestReward = model.claimWeeklyChest() }
                    if !board.companion.isEmpty {
                        section("Companion", resets: "This week", quests: board.companion)
                    }
                    Text("Quests track your walks automatically. Rewards you've claimed are yours to keep when quests reset.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Quests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { CoinBadge(coins: model.wallet.coins) }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: chestReward)
    }

    private func section(_ title: String, resets: String, quests: [QuestStatus]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Spacer()
                Label(resets, systemImage: "clock")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            if quests.isEmpty {
                Text("Nothing here right now.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            ForEach(quests) { QuestRow(status: $0) }
        }
        .pixelPanel()
    }
}

/// One quest: title, progress, reward and the claim button.
struct QuestRow: View {
    @Environment(AppModel.self) private var model
    let status: QuestStatus
    var compact = false
    @State private var justClaimed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .fill(status.isComplete ? Theme.Palette.leaf.opacity(0.35) : Theme.Palette.forestRaised)
                Image(systemName: status.isClaimed ? "checkmark" : icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(status.isComplete ? Theme.Palette.cream : Theme.Palette.creamDim)
            }
            .frame(width: 32, height: 32)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(status.quest.title)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(status.isClaimed ? Theme.Palette.creamDim : Theme.Palette.cream)
                    .strikethrough(status.isClaimed, color: Theme.Palette.creamDim)
                if !status.isClaimed {
                    HStack(spacing: Theme.Spacing.s) {
                        PixelProgressBar(fraction: status.fraction, segments: compact ? 8 : 12,
                                         fill: status.isComplete ? Theme.Palette.leaf : Theme.Palette.gold, height: 8)
                        Text(progressText)
                            .font(Theme.Typography.micro.monospacedDigit())
                            .foregroundStyle(Theme.Palette.creamDim)
                            .fixedSize()
                    }
                }
                Text("+\(status.quest.coins) coins · +\(status.quest.xp) XP")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.gold.opacity(status.isClaimed ? 0.5 : 1))
            }
            Spacer(minLength: 0)
            if status.isClaimable {
                Button("Claim") {
                    if model.claimQuest(status) != nil { justClaimed.toggle() }
                }
                .buttonStyle(.pixel)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: status.isClaimable)
        .sensoryFeedback(.success, trigger: justClaimed)
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.isClaimed ? "Claimed" : status.isComplete ? "Complete, ready to claim" : progressText)
    }

    private var progressText: String {
        let target = status.quest.goal.target
        switch status.quest.goal {
        case .metersToday, .metersThisWeek, .teamMetersThisWeek:
            return "\(DistanceFormatting.kilometres(status.progress)) / \(DistanceFormatting.kilometres(target))"
        case .stepsToday:
            return "\(DistanceFormatting.steps(status.progress)) / \(DistanceFormatting.steps(target))"
        default:
            return "\(status.progress) / \(target)"
        }
    }

    private var icon: String {
        switch status.quest.goal {
        case .stepsToday: return "shoeprints.fill"
        case .metersToday, .metersThisWeek: return "figure.walk"
        case .chestsOpenedToday, .chestsFoundThisWeek: return "shippingbox.fill"
        case .coinsEarnedToday: return "circle.circle.fill"
        case .newZonesToday, .newZonesThisWeek: return "map.fill"
        case .walkWithFriendToday: return "person.2.fill"
        case .activeDaysThisWeek: return "calendar"
        case .expeditionCompletedThisWeek, .teamMetersThisWeek: return "flag.fill"
        case .companionGrowsThisWeek: return "leaf.fill"
        }
    }
}

/// The reward for finishing every weekly quest.
private struct WeeklyChestCard: View {
    let board: QuestBoard
    let open: () -> Void

    var body: some View {
        let done = board.weekly.filter(\.isClaimed).count
        HStack(spacing: Theme.Spacing.m) {
            ItemIcon(spriteID: "chest", pixel: 4, locked: !board.weeklyChestReady && !board.weeklyChestClaimed)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Weekly chest")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text(board.weeklyChestClaimed ? "Opened. A new one arrives Monday."
                     : "Claim all \(board.weekly.count) weekly quests to open it. \(done)/\(board.weekly.count) done.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Text("+\(board.weeklyChest.coins) coins · +\(board.weeklyChest.xp) XP")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.gold)
                if board.weeklyChestReady {
                    Button("Open chest", action: open)
                        .buttonStyle(.pixel)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .pixelPanel(fill: board.weeklyChestReady ? Theme.Palette.forestRaised : Theme.Palette.forestDeep)
    }
}
