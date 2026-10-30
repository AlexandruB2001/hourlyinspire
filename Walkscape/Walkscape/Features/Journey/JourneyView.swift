import SwiftUI
import WalkscapeDomain

/// The main screen: today's walk as a journey through the world.
struct JourneyView: View {
    @Environment(AppModel.self) private var model
    @State private var guide: GuideSection.ID?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    JourneyHero(topInset: proxy.safeAreaInsets.top) { guide = .journey }
                    VStack(spacing: Theme.Spacing.l) {
                        if let tip = model.journeyTip {
                            TipCard(tip: tip) { guide = $0 }
                        }
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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.journeyTip)
        .sheet(item: $guide) { GuideView(start: $0) }
    }
}

/// The large animated scene at the top of the Journey screen.
private struct JourneyHero: View {
    @Environment(AppModel.self) private var model
    let topInset: CGFloat
    let openGuide: () -> Void

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
            .overlay(alignment: .topTrailing) {
                GuideButton(action: openGuide)
                    .padding(.top, topInset + Theme.Spacing.s)
                    .padding(.trailing, Theme.Spacing.l)
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
            // The scene itself is hidden from VoiceOver; the chips, chests and guide button stay reachable.
            .accessibilityElement(children: .contain)
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
/// The small Apple Health sync chip on the Journey scene. Tap it for what
/// it means and what to do.
struct DataSourceChip: View {
    @Environment(AppModel.self) private var model
    @State private var explaining = false

    var body: some View {
        let state = model.healthSyncIndicator
        Button { explaining = true } label: { chip(state) }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.3), value: state)
            .accessibilityLabel(accessibilityText(state))
            .accessibilityHint("Explains your Apple Health sync")
            .sheet(isPresented: $explaining) {
                HealthSyncSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder private func chip(_ state: HealthSyncIndicator) -> some View {
        switch state {
        case .demo:
            StatusChip(text: "Demo data · not from Apple Health", systemImage: "sparkles", tint: Theme.Palette.crystal)
        case .synced(let date):
            StatusChip(text: "Synced · \(RelativeTime.short(since: date, now: model.now))", systemImage: "checkmark.circle.fill",
                       tint: Theme.Palette.leaf)
        case .syncing:
            StatusChip(text: "Syncing steps…", systemImage: "arrow.triangle.2.circlepath")
        case .noStepsYet:
            StatusChip(text: "Synced · no steps yet today", systemImage: "checkmark.circle", tint: Theme.Palette.cream)
        case .stale(let date):
            StatusChip(text: "Last synced \(RelativeTime.short(since: date, now: model.now))", systemImage: "clock",
                       tint: Theme.Palette.gold)
        case .needsAccess:
            StatusChip(text: "Health access needed", systemImage: "heart.text.square", tint: Theme.Palette.ember)
        case .unavailable:
            StatusChip(text: "Apple Health unavailable", systemImage: "heart.slash", tint: Theme.Palette.ember)
        case .problem:
            StatusChip(text: "Couldn't sync · tap for help", systemImage: "exclamationmark.triangle.fill", tint: Theme.Palette.ember)
        }
    }

    private func accessibilityText(_ state: HealthSyncIndicator) -> String {
        switch state {
        case .demo: return "Showing demo data, not your Apple Health data"
        case .synced(let date): return "Apple Health synced \(RelativeTime.short(since: date, now: model.now))"
        case .syncing: return "Syncing your steps from Apple Health"
        case .noStepsYet: return "Apple Health synced. No steps recorded yet today"
        case .stale(let date): return "Apple Health last synced \(RelativeTime.short(since: date, now: model.now)). This may be out of date."
        case .needsAccess: return "Apple Health access is needed"
        case .unavailable: return "Apple Health isn't available on this device"
        case .problem: return "Apple Health couldn't sync"
        }
    }
}

/// What the sync chip means, with the action that fixes it.
private struct HealthSyncSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        let state = model.healthSyncIndicator
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Eyebrow("Apple Health", color: state.needsAttention ? Theme.Palette.ember : Theme.Palette.gold)
            Text(title(state))
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.cream)
            Text(explanation(state))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.cream.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            actions(state)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.night.ignoresSafeArea())
    }

    private func title(_ state: HealthSyncIndicator) -> String {
        switch state {
        case .demo: return "You're using demo data"
        case .synced: return "Your walking is up to date"
        case .syncing: return "Syncing your steps"
        case .noStepsYet: return "No steps yet today"
        case .stale: return "Waiting for new data"
        case .needsAccess: return "Connect Apple Health"
        case .unavailable: return "Apple Health isn't available"
        case .problem: return "Couldn't read Apple Health"
        }
    }

    private func explanation(_ state: HealthSyncIndicator) -> String {
        switch state {
        case .demo:
            return "These numbers are sample data for trying Walkscape out. Switch to Apple Health in your Profile to walk for real."
        case .synced:
            return "Walkscape has your latest steps and distance from Apple Health. New walking appears when you open the app, and now and then in the background."
        case .syncing:
            return "Walkscape is reading today's steps and distance from Apple Health. This usually takes a moment."
        case .noStepsYet:
            return "Apple Health has nothing recorded since midnight. If you have walked, Walkscape may not be allowed to read your data: in the Health app, tap your profile picture, then Apps › Walkscape, and turn on Steps and Walking + Running Distance."
        case .stale:
            return "The last update is a while ago. Health data can't be read while your iPhone is locked, and steps from an Apple Watch can take a few minutes to arrive."
        case .needsAccess:
            return "Walkscape reads only your steps and walking distance to move your character. Nothing is written to Health and no location is used."
        case .unavailable:
            return "This device doesn't have Apple Health, so Walkscape can't read your walking. You can explore with demo data instead."
        case .problem(let error):
            switch error {
            case .queryFailed(let detail) where detail.contains("locked"):
                return "Health data can't be read while your iPhone is locked. Unlock it and try again."
            default:
                return "Something went wrong reading Apple Health. Try again in a moment. If it keeps happening, check that Walkscape can read Steps and Walking + Running Distance in the Health app."
            }
        }
    }

    @ViewBuilder private func actions(_ state: HealthSyncIndicator) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            switch state {
            case .needsAccess:
                Button("Connect Apple Health") { Task { await model.connectAppleHealth(); dismiss() } }
                    .buttonStyle(.pixel)
            case .unavailable:
                Button("Use demo data") { model.switchDataSource(to: .demo); dismiss() }
                    .buttonStyle(.pixel)
            case .noStepsYet, .problem:
                Button("Try again") { Task { await model.refreshWalking() } }
                    .buttonStyle(.pixel)
                Button("Open the Health app") {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                }
                .buttonStyle(.pixelQuiet)
            case .synced, .stale, .syncing:
                Button("Sync now") { Task { await model.refreshWalking() } }
                    .buttonStyle(.pixelSecondary)
                    .disabled(state == .syncing)
            case .demo:
                EmptyView()
            }
        }
    }
}
