import SwiftUI
import WalkscapeDomain

/// The main screen: today's walk as a journey through the world.
struct JourneyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    JourneyHero(topInset: proxy.safeAreaInsets.top)
                    VStack(spacing: Theme.Spacing.l) {
                        DistanceCard()
                        if let run = model.activeEventRuns.first { SeasonalEventCard(run: run) }
                        QuestsCard()
                        WorldEventsCard()
                        HealthStatusCard()
                        CompanionCard()
                        TrailStrip()
                        NextZoneCard()
                        FriendsPreviewCard()
                        if model.isDemo { DemoControlsCard() }
                        ShareJourneyButton()
                        JourneyJournalSection()
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, -Theme.Spacing.xxl - Theme.Spacing.l)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await model.refreshAll() }
        }
        .background(Theme.Palette.night.ignoresSafeArea())
    }
}

/// The large animated scene at the top of the Journey screen.
private struct JourneyHero: View {
    @Environment(AppModel.self) private var model
    let topInset: CGFloat

    var body: some View {
        let zone = model.zoneProgress.currentZone
        PixelSceneView(biome: zone.biome, avatarID: model.settings.avatarID, outfit: model.outfit,
                       companionImage: model.companion.flatMap {
                           PixelArtCache.shared.companion($0.speciesID, kilometres: model.companionGrowth?.kilometres ?? 0,
                                                          accessories: $0.wornAccessories, skin: model.companionSkin)
                       },
                       companionSpeciesID: model.companion?.speciesID,
                       walking: model.distanceMeters > 0, season: model.season,
                       eventSpriteID: model.todaysEvents.first { $0.zoneID == zone.id && !model.hasFound($0) }?.event.spriteID,
                       trail: TrailEffectCatalog.effect(withID: model.currentLook.trailEffectID))
            .id(zone.biome)
            .transition(.opacity)
            .frame(height: 330 + topInset)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Theme.Palette.night], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
            .overlay(alignment: .top) {
                VStack(spacing: Theme.Spacing.s) {
                    ZoneSign(zone: zone)
                    HStack(spacing: Theme.Spacing.s) {
                        DataSourceChip()
                        CoinBadge(coins: model.wallet.coins)
                    }
                }
                .padding(.top, topInset + Theme.Spacing.s)
            }
            .overlay(alignment: .bottomTrailing) {
                ChestPopUp()
                    .padding(.trailing, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xxl + Theme.Spacing.xl)
            }
            .overlay(alignment: .bottomLeading) {
                ReferralChestPopUp()
                    .padding(.leading, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xxl + Theme.Spacing.xl)
            }
            .animation(.easeInOut(duration: 0.8), value: zone.biome)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You are in \(zone.name). \(zone.tagline)")
    }
}

/// A chest found on today's walk. It bounces on the path until it's opened.
private struct ChestPopUp: View {
    @Environment(AppModel.self) private var model
    @State private var bounce = false
    @State private var reward: Int?
    @State private var opened = 0

    var body: some View {
        let pending = model.wallet.pendingChests
        VStack(spacing: Theme.Spacing.xs) {
            if let reward {
                Text("+\(reward) coins")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.gold)
                    .shadow(color: Theme.Palette.ink, radius: 0, x: 0, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if pending > 0 {
                Button {
                    if let coins = model.openChest() {
                        reward = coins
                        opened += 1
                    }
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        ItemIcon(spriteID: "chest", pixel: 4)
                            .offset(y: bounce ? -6 : 0)
                        StatusChip(text: pending > 1 ? "\(pending) chests · tap" : "Chest! Tap to open",
                                   systemImage: "hand.tap.fill", tint: Theme.Palette.gold)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(pending > 1 ? "\(pending) chests found on your walk" : "A chest found on your walk")
                .accessibilityHint("Opens a chest for \(CoinRules.standard.coinsPerChest) coins")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: pending)
        .animation(.easeOut(duration: 0.3), value: reward)
        .sensoryFeedback(.success, trigger: opened)
        .task(id: opened) {
            guard opened > 0 else { return }
            try? await Task.sleep(for: .seconds(1.4))
            reward = nil
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { bounce = true }
        }
    }
}

/// A wooden signpost with the current zone's name.
private struct ZoneSign: View {
    let zone: Zone

    var body: some View {
        VStack(spacing: 2) {
            Text(zone.name.uppercased())
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.cream)
            Text(zone.tagline)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.cream.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(Theme.Palette.bark)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 2).padding(.horizontal, 4).padding(.top, 2)
                }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
        .shadow(color: Theme.Palette.ink.opacity(0.4), radius: 0, x: 0, y: 3)
        .padding(.horizontal, Theme.Spacing.xl)
    }
}

/// "Apple Health · Updated 2 min ago" or "Demo data".
struct DataSourceChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let freshness = model.freshness
        let updated = model.sync.lastSuccessfulRefresh.map { RelativeTime.short(since: $0, now: model.now) }
        Group {
            if model.isDemo {
                StatusChip(text: "Demo data · not from Apple Health", systemImage: "sparkles", tint: Theme.Palette.crystal)
            } else if model.sync.phase == .loading && updated == nil {
                StatusChip(text: "Reading Apple Health…", systemImage: "heart.fill")
            } else if let updated {
                StatusChip(text: "Apple Health · updated \(updated)",
                           systemImage: freshness == .stale ? "exclamationmark.triangle.fill" : "heart.fill",
                           tint: freshness == .stale ? Theme.Palette.ember : Theme.Palette.cream)
            } else {
                StatusChip(text: "Apple Health · not synced yet", systemImage: "heart")
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if model.isDemo { return "Showing demo data, not your Apple Health data" }
        guard let last = model.sync.lastSuccessfulRefresh else { return "Apple Health has not synced yet" }
        let stale = model.freshness == .stale ? ". This data may be out of date." : ""
        return "Apple Health data updated \(RelativeTime.short(since: last, now: model.now))\(stale)"
    }
}
