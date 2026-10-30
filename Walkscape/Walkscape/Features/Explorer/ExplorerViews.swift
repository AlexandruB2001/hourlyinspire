import SwiftUI
import WalkscapeDomain

/// "Lv 7" chip with a tiny XP bar, on the Journey distance card. Opens Profile.
struct ExplorerBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let level = model.explorerLevel
        Button { model.selectedTab = .profile } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Lv \(level.level)")
                    .font(Theme.Typography.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Theme.Palette.gold)
                PixelProgressBar(fraction: level.fraction, segments: 6, fill: Theme.Palette.gold, height: 6)
                    .frame(width: 34)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.Palette.ink.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explorer level \(level.level)")
        .accessibilityHint("Opens your profile")
    }
}

/// Lifetime Explorer Level on the Profile tab: never resets, unlike the daily journey.
struct ExplorerLevelCard: View {
    @Environment(AppModel.self) private var model
    @State private var showsBreakdown = false

    var body: some View {
        let xp = model.explorerXP
        let level = ExplorerLevel(totalXP: xp.total)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                LevelMedal(level: level.level, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("Explorer level", color: Theme.Palette.gold)
                    Text("Level \(level.level)")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.cream)
                    Text(level.xpForNextLevel.map { "\($0 - level.xpIntoLevel) XP to level \(level.level + 1)" } ?? "Max level. Legendary!")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                Spacer(minLength: 0)
            }
            PixelProgressBar(fraction: level.fraction, segments: 16)
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: level.fraction)
            Button {
                withAnimation { showsBreakdown.toggle() }
            } label: {
                Label("\(xp.total) XP earned", systemImage: showsBreakdown ? "chevron.down" : "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            }
            if showsBreakdown {
                VStack(spacing: Theme.Spacing.xs) {
                    row("Walking", xp.walking)
                    row("Zones discovered", xp.zones)
                    row("Relics found", xp.relics)
                    row("Achievements", xp.achievements)
                    row("Quests & rewards", xp.rewards)
                }
                Text("XP never resets. Each level gives \(ExplorerRules.standard.coinsPerLevel) coins.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .pixelPanel()
        .accessibilityElement(children: .contain)
    }

    private func row(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.cream)
            Spacer()
            Text("\(value) XP").font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.Palette.creamDim)
        }
    }
}

/// A pixel-style medal with the level number.
struct LevelMedal: View {
    let level: Int
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.gold)
            Circle().strokeBorder(Theme.Palette.ink, lineWidth: 3)
            Circle().inset(by: size * 0.14).strokeBorder(Theme.Palette.ink.opacity(0.35), lineWidth: 2)
            Text("\(level)")
                .font(.system(size: size * 0.4, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Palette.ink)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Shown when the Explorer Level goes up.
struct LevelUpBanner: View {
    let level: Int
    let dismiss: () -> Void
    @State private var pop = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            LevelMedal(level: level, size: 46)
                .scaleEffect(pop ? 1 : 0.4)
                .rotationEffect(.degrees(pop ? 0 : -25))
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Level up!", color: Theme.Palette.gold)
                Text("Explorer Level \(level)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                HStack(spacing: Theme.Spacing.xs) {
                    ItemIcon(spriteID: "coin", pixel: 1.6)
                    Text("+\(ExplorerRules.standard.coinsPerLevel) coins")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Theme.Palette.gold)
        }
        .pixelPanel(fill: Theme.Palette.forestRaised, padding: Theme.Spacing.m)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .onTapGesture(perform: dismiss)
        .sensoryFeedback(.success, trigger: level)
        .task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { pop = true }
            try? await Task.sleep(for: .seconds(5))
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level up. Explorer Level \(level)")
        .accessibilityAddTraits(.isButton)
    }
}
