import SwiftUI
import WalkscapeDomain

/// Your companion and how close it is to growing.
struct CompanionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let companion = model.companion, let species = companion.species, let growth = model.companionGrowth {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                    PixelImageView(image: PixelArtCache.shared.companion(species.id, kilometres: growth.kilometres,
                                                                        accessories: companion.wornAccessories), pixel: 3.4)
                }
                .frame(width: 76, height: 76)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.ink, lineWidth: 2))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Eyebrow("Your companion")
                    Text("\(species.name) · \(growth.stage.name)")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    if let left = growth.kilometresToNextStage, let next = growth.stage.next {
                        Text("\(growth.kilometres) km together · \(left) km until it becomes a \(next.name)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                        PixelProgressBar(fraction: growth.fractionToNextStage, segments: 10, fill: Theme.Palette.leaf, height: 10)
                    } else {
                        Text("\(growth.kilometres) km together. Fully grown, and glowing.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.gold)
                    }
                    Text("\u{201C}\(model.companionLine)\u{201D}")
                        .font(Theme.Typography.micro.italic())
                        .foregroundStyle(Theme.Palette.cream.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            .pixelPanel()
            .accessibilityElement(children: .combine)
        }
    }
}

/// "Share my journey": a card of where you are right now.
struct ShareJourneyButton: View {
    @Environment(AppModel.self) private var model
    @State private var card: MilestoneCardContent?

    var body: some View {
        Button {
            card = .currentProgress(model)
        } label: {
            Label("Share my journey", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pixelQuiet)
        .sheet(item: $card) { ShareCardSheet(content: $0) }
    }
}

/// The permanent log of the journey, newest first.
struct JourneyJournalSection: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false
    @State private var sharing: MilestoneCardContent?

    private let collapsedCount = 6

    var body: some View {
        let entries = model.journal.timeline
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Journey Journal") {
                ItemIcon(spriteID: "journal", pixel: 2)
            }
            if entries.isEmpty {
                Text("Your milestones are written here as you walk: new zones, relics, big days and your companion growing up.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                ForEach(showAll ? entries : Array(entries.prefix(collapsedCount))) { entry in
                    JournalRow(entry: entry) { sharing = .journal(entry, model: model) }
                }
                if entries.count > collapsedCount {
                    Button(showAll ? "Show fewer" : "Show all \(entries.count) entries") {
                        withAnimation(.easeInOut) { showAll.toggle() }
                    }
                    .buttonStyle(.pixelQuiet)
                }
            }
        }
        .pixelPanel()
        .sheet(item: $sharing) { ShareCardSheet(content: $0) }
    }
}

private struct JournalRow: View {
    let entry: JournalEntry
    let share: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            JournalIcon(iconID: entry.iconID)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.cream)
                Text(entry.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Text(entry.day.displayDate)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.gold.opacity(0.8))
            }
            Spacer(minLength: 0)
            Button(action: share) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.Palette.creamDim)
                    .padding(Theme.Spacing.xs)
            }
            .accessibilityLabel("Share \(entry.title)")
        }
        .accessibilityElement(children: .combine)
    }
}

/// Chests from friends you invited, once they've started walking.
struct ReferralChestPopUp: View {
    @Environment(AppModel.self) private var model
    @State private var reward: Int?
    @State private var opened = 0
    @State private var bounce = false

    var body: some View {
        let chests = model.referralChests
        VStack(spacing: Theme.Spacing.xs) {
            if let reward {
                Text("+\(reward) coins")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.gold)
                    .shadow(color: Theme.Palette.ink, radius: 0, x: 0, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let chest = chests.first {
                Button {
                    if let coins = model.openReferralChest(chest) {
                        reward = coins
                        opened += 1
                    }
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        ItemIcon(spriteID: "referral-chest", pixel: 4)
                            .offset(y: bounce ? -6 : 0)
                        StatusChip(text: chests.count > 1 ? "\(chests.count) invite chests" : "Invite chest!",
                                   systemImage: "gift.fill", tint: Theme.Palette.gold)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("A referral chest from a friend you invited")
                .accessibilityHint("Opens it for 25 to 100 coins")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: chests.count)
        .animation(.easeOut(duration: 0.3), value: reward)
        .sensoryFeedback(.success, trigger: opened)
        .task(id: opened) {
            guard opened > 0 else { return }
            try? await Task.sleep(for: .seconds(1.6))
            reward = nil
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bounce = true }
        }
    }
}

extension LocalDay {
    /// "28 Oct 2026" in the user's locale.
    var displayDate: String {
        interval(in: .current).start.formatted(date: .abbreviated, time: .omitted)
    }

    var weekdayName: String {
        interval(in: .current).start.formatted(.dateTime.weekday(.wide))
    }
}
