import SwiftUI
import WalkscapeDomain

/// Spend coins from walking on Mystery Boxes: the only way to get outfits
/// for your walker and accessories for your companion.
struct ShopView: View {
    @Environment(AppModel.self) private var model
    /// Nil shows every slot.
    @State private var slot: EquipmentSlot?
    @State private var revealed: MysteryBoxPrize?
    /// Coins back when the revealed prize was a duplicate.
    @State private var revealedRefund: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    WardrobeHeader()
                    if StoreFeature.isEnabled { StoreEntryCard() }
                    DailyChestCard()
                    MysteryBoxCard { prize, refund in
                        revealedRefund = refund
                        revealed = prize
                    }
                    RewardedAdCard()
                    CompanionAccessoriesCard()
                    SlotPicker(selection: $slot)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.m)],
                              spacing: Theme.Spacing.m) {
                        ForEach(items) { ShopItemCard(item: $0) }
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Shop")
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { CoinBadge(coins: model.wallet.coins) }
            }
            .sheet(item: $revealed) { MysteryRevealSheet(prize: $0, refund: revealedRefund) }
            .task { await model.refreshDailyChest() }
        }
    }

    private var items: [ShopItem] {
        ShopCatalog.items
            .filter { slot == nil || $0.slot == slot }
            .sorted { ($0.rarity, $0.slot.rawValue) < ($1.rarity, $1.slot.rawValue) }
    }
}

private struct WardrobeHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rules = CoinRules.standard
        let owned = ShopCatalog.items.filter(model.wallet.owns).count
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                WalkingCharacter(avatarID: model.settings.avatarID, outfit: model.outfit, walking: true, pixel: 4)
            }
            .frame(width: 92, height: 112)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.ink, lineWidth: 2))

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatBlock(value: "\(model.wallet.coins)", label: "coins to spend")
                Text("Earn \(rules.coinsPerKilometre) coins every kilometre. Chests on the trail hold \(WalletState.chestCoinRange.lowerBound)\u{2013}\(WalletState.chestCoinRange.upperBound) more.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Text("\(owned)/\(ShopCatalog.items.count) outfit pieces collected")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            }
            Spacer(minLength: 0)
        }
        .pixelPanel()
    }
}

private struct MysteryBoxCard: View {
    @Environment(AppModel.self) private var model
    let onReveal: (MysteryBoxPrize, Int?) -> Void
    @State private var opening = false
    @State private var confirming = false
    @State private var problem: String?

    var body: some View {
        let price = ShopCatalog.mysteryBoxPrice
        let ownsEverything = MysteryBox.prizes(on: model.today).allSatisfy { model.wallet.owns(itemID: $0.id) }
        let refunds = Rarity.allCases.map { "\($0.duplicateRefund)" }.joined(separator: "/")
        let odds = Rarity.allCases.map { "\($0.mysteryBoxWeight)% \($0.rawValue)" }.joined(separator: " · ")
        HStack(spacing: Theme.Spacing.m) {
            ItemIcon(spriteID: "mystery-box", pixel: 5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Mystery Box")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text(ownsEverything ? "You own everything! Every box now gives coins back."
                     : "The only way to get new looks: a random outfit piece or companion accessory. Duplicates give \(refunds) coins back by rarity.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Text(odds)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim.opacity(0.8))
                Button {
                    confirming = true
                } label: {
                    if opening {
                        ProgressView().tint(Theme.Palette.ink)
                    } else {
                        PriceLabel(text: "Open for", price: price)
                    }
                }
                .buttonStyle(.pixel)
                .disabled(opening || model.wallet.coins < price)
                .opacity(model.wallet.coins < price ? 0.5 : 1)
                .padding(.top, Theme.Spacing.xs)
                // A mis-tap shouldn't spend coins.
                .confirmationDialog("Open a Mystery Box?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Open for \(price) coins") { open() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("\(price) coins from your \(model.wallet.coins). Duplicates give coins back.")
                }
                if let problem {
                    Text(problem)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.ember)
                }
            }
            Spacer(minLength: 0)
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }

    private func open() {
        opening = true
        problem = nil
        Task {
            let result = await model.openMysteryBox()
            opening = false
            switch result {
            case .won(let prize): onReveal(prize, nil)
            case .duplicate(let prize, let refund): onReveal(prize, refund)
            case .notEnoughCoins(let needed): problem = "You need \(needed) more coins."
            case .soldOut: problem = "The box is empty right now. Try again later."
            case .unavailable(let message): problem = message
            }
        }
    }
}

/// A free chest every 24 hours, with a countdown to the next one.
private struct DailyChestCard: View {
    @Environment(AppModel.self) private var model
    @State private var opening = false
    @State private var won: Int?
    @State private var problem: String?
    @State private var bounce = false

    var body: some View {
        let range = DailyChest.range
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let readyAt = model.dailyChestReadyAt
            let ready = readyAt.map { $0 <= context.date } ?? false
            HStack(spacing: Theme.Spacing.m) {
                ItemIcon(spriteID: "chest", pixel: 5)
                    .offset(y: ready && bounce ? -4 : 0)
                    .opacity(ready || won != nil ? 1 : 0.6)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Daily Chest")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    Text("Free once a day: \(range.lowerBound) to \(range.upperBound) coins. Big amounts are rare!")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                    if let won {
                        Text("+\(won) coins!")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Palette.gold)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if let readyAt, !ready {
                        Label("Next chest in \(Self.countdown(to: readyAt, from: context.date))", systemImage: "clock.fill")
                            .font(Theme.Typography.caption.monospacedDigit().weight(.heavy))
                            .foregroundStyle(Theme.Palette.gold)
                            .accessibilityLabel("Next chest in \(Self.spokenCountdown(to: readyAt, from: context.date))")
                    } else if ready {
                        Button {
                            open()
                        } label: {
                            if opening {
                                ProgressView().tint(Theme.Palette.ink)
                            } else {
                                Label("Open free chest", systemImage: "gift.fill")
                            }
                        }
                        .buttonStyle(.pixel)
                        .disabled(opening)
                        .padding(.top, Theme.Spacing.xs)
                    } else {
                        Text(model.dataSource == .appleHealth && !model.isSignedIn
                             ? "Sign in on the Profile tab to open a free chest every day." : "Checking your chest\u{2026}")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                    if let problem {
                        Text(problem)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.ember)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: won)
        .sensoryFeedback(.success, trigger: won)
        .accessibilityElement(children: .contain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { bounce = true }
        }
    }

    private func open() {
        opening = true
        problem = nil
        Task {
            let result = await model.openDailyChest()
            opening = false
            switch result {
            case .opened(let coins): won = coins
            case .notReady: problem = "Already opened. The countdown shows when the next one is ready."
            case .unavailable(let message): problem = message
            }
        }
    }

    /// "13:42:05", or "42:05" in the last hour.
    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func spokenCountdown(to date: Date, from now: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter.string(from: max(60, date.timeIntervalSince(now))) ?? ""
    }
}

/// Watch a short ad for a few coins, a few times a day.
private struct RewardedAdCard: View {
    @Environment(AppModel.self) private var model
    @State private var earned: Int?
    @State private var failed = false

    var body: some View {
        let rules = AdRules.standard
        let left = model.rewardedAdsLeft
        HStack(spacing: Theme.Spacing.m) {
            ItemIcon(spriteID: "coin", pixel: 4)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Watch an ad")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text(left > 0
                     ? "A short video for \(rules.rewardedCoins) coins. \(left) of \(rules.rewardedPerDay) left today."
                     : "That's all for today. More tomorrow, or earn coins on a walk!")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                if let earned {
                    Text("+\(earned) coins. Thanks for supporting Walkscape!")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.gold)
                } else if failed {
                    Text("No ad was ready, or it closed early. Try again in a moment.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.ember)
                }
                if left > 0 {
                    Button {
                        earned = nil
                        failed = false
                        Task {
                            earned = await model.watchRewardedAd()
                            failed = earned == nil
                        }
                    } label: {
                        if model.isWatchingAd {
                            ProgressView().tint(Theme.Palette.ink)
                        } else {
                            Label("Watch for \(rules.rewardedCoins)", systemImage: "play.rectangle.fill")
                        }
                    }
                    .buttonStyle(.pixelSecondary)
                    .disabled(model.isWatchingAd || !model.ads.canRequestAds)
                    .opacity(model.ads.canRequestAds ? 1 : 0.5)
                    .padding(.top, Theme.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .pixelPanel()
        .sensoryFeedback(.success, trigger: earned)
        .accessibilityElement(children: .contain)
    }
}

/// Hats, scarves and backpacks for your companion.
private struct CompanionAccessoriesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let companion = model.companion, let species = companion.species {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "For \(species.name)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(CompanionAccessoryCatalog.all.filter { StoreFeature.shows(accessoryID: $0.id) }) { accessory in
                            tile(accessory, companion: companion)
                        }
                    }
                }
                Text("Accessories come from the Mystery Box. A few are gifts for Explorer Levels 5, 10 and 15 or festival rewards.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            .pixelPanel()
        }
    }

    private func tile(_ accessory: CompanionAccessory, companion: CompanionState) -> some View {
        let owned = model.wallet.owns(itemID: accessory.id)
        let wearing = companion.wornAccessories.contains(accessory.id)
        let growth = model.companionGrowth?.kilometres ?? 0
        return VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.skyMuted)
                PixelImageView(image: PixelArtCache.shared.companion(companion.speciesID, kilometres: growth,
                                                                    accessories: [accessory.id]), pixel: 3)
            }
            .frame(width: 84, height: 72)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                .strokeBorder(wearing ? Theme.Palette.gold : Theme.Palette.ink, lineWidth: 2))
            Text(accessory.name)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.cream)
                .lineLimit(1)
                .frame(width: 84)
            if owned {
                Button(wearing ? "Wearing" : "Wear") { model.toggleAccessory(accessory) }
                    .buttonStyle(PixelButtonStyle(kind: wearing ? .secondary : .quiet))
            } else if !accessory.isInMysteryBox(on: model.today), let event = accessory.eventID.flatMap(SeasonalEventCatalog.event(withID:)) {
                Text("\(event.name) reward")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.gold)
                    .multilineTextAlignment(.center)
                    .frame(width: 84)
            } else if let rarity = accessory.rarity {
                InMysteryBoxLabel(rarity: rarity)
            } else if PlusMonthlyGift.rotation.contains(accessory.id) {
                Text("Plus gift")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.gold)
            } else if let level = accessory.unlockLevel {
                Text("Level \(level)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessory.name)
    }
}

private struct SlotPicker: View {
    @Binding var selection: EquipmentSlot?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                chip("All", isSelected: selection == nil) { selection = nil }
                ForEach(EquipmentSlot.allCases, id: \.self) { slot in
                    chip(slot.displayName, isSelected: selection == slot) { selection = slot }
                }
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PixelButtonStyle(kind: isSelected ? .primary : .quiet))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ShopItemCard: View {
    @Environment(AppModel.self) private var model
    let item: ShopItem

    var body: some View {
        let owned = model.wallet.owns(item)
        let wearing = model.wallet.isEquipped(item)
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.skyMuted)
                if let trail = Contrails.effect(forItemID: item.id) {
                    TrailPreview(effect: trail, avatarID: model.settings.avatarID)
                } else {
                    PixelImageView(image: PixelArtCache.shared.characterFrame(0, avatarID: model.settings.avatarID,
                                                                              outfit: [item.id], walking: false),
                                   pixel: 3)
                }
            }
            .frame(height: 84)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                .strokeBorder(wearing ? Theme.Palette.gold : item.rarity.color.opacity(0.7), lineWidth: 2))

            VStack(spacing: 2) {
                Text(item.name)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                RarityTag(rarity: item.rarity)
            }

            if owned {
                Button(wearing ? "Wearing" : "Wear") { model.toggleEquipped(item) }
                    .buttonStyle(PixelButtonStyle(kind: wearing ? .secondary : .quiet))
            } else {
                InMysteryBoxLabel(rarity: nil)
            }
        }
        .pixelPanel(padding: Theme.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(item.rarity.displayName). \(item.detail)")
        .accessibilityValue(owned ? (wearing ? "Wearing" : "Owned") : "Not found yet. Comes from the Mystery Box")
    }
}

private struct MysteryRevealSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prize: MysteryBoxPrize
    /// Coins back when this was a duplicate.
    var refund: Int?
    @State private var shown = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Eyebrow(refund == nil ? "\(prize.rarity.displayName) find!" : "Duplicate \(prize.rarity.displayName.lowercased())!",
                    color: prize.rarity.color)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                Group {
                    if let trail = Contrails.effect(forItemID: prize.id) {
                        TrailPreview(effect: trail, avatarID: model.settings.avatarID, pixel: 5)
                    } else {
                        PixelImageView(image: image, pixel: 6)
                    }
                }
                .scaleEffect(shown ? 1 : 0.4)
                .rotationEffect(.degrees(shown ? 0 : -20))
            }
            .frame(width: 150, height: 170)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(prize.rarity.color, lineWidth: 3))
            VStack(spacing: Theme.Spacing.xs) {
                Text(prize.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                Text(detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .multilineTextAlignment(.center)
                if let refund {
                    Label("You already have this: +\(refund) coins back", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(Theme.Typography.caption.weight(.heavy))
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            HStack(spacing: Theme.Spacing.m) {
                Button(wearLabel) {
                    wear()
                    dismiss()
                }
                .buttonStyle(.pixel)
                Button("Keep walking") { dismiss() }
                    .buttonStyle(.pixelQuiet)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.forestDeep.ignoresSafeArea())
        .presentationDetents([.medium])
        .sensoryFeedback(.success, trigger: shown)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { shown = true } }
    }

    private var image: CGImage? {
        switch prize {
        case .outfit(let item):
            return PixelArtCache.shared.characterFrame(0, avatarID: model.settings.avatarID, outfit: [item.id], walking: false)
        case .accessory(let accessory, _):
            guard let companion = model.companion else { return PixelArtCache.shared.item("mystery-box") }
            return PixelArtCache.shared.companion(companion.speciesID, kilometres: model.companionGrowth?.kilometres ?? 0,
                                                  accessories: [accessory.id])
        }
    }

    private var detail: String {
        switch prize {
        case .outfit(let item): return item.detail
        case .accessory: return "For your companion. Find it in the Shop under your companion's accessories."
        }
    }

    private var wearLabel: String {
        if case .accessory = prize { return model.companion?.wornAccessories.contains(prize.id) == true ? "Lovely!" : "Put it on" }
        return "Wear it"
    }

    private func wear() {
        switch prize {
        case .outfit(let item):
            if !model.wallet.isEquipped(item) { model.toggleEquipped(item) }
        case .accessory(let accessory, _):
            if model.companion?.wornAccessories.contains(accessory.id) == false { model.toggleAccessory(accessory) }
        }
    }
}

/// "In the Mystery Box" for things not found yet.
private struct InMysteryBoxLabel: View {
    let rarity: Rarity?

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ItemIcon(spriteID: "mystery-box", pixel: 1.4)
            Text("Mystery Box")
        }
        .font(Theme.Typography.micro)
        .foregroundStyle(rarity?.color ?? Theme.Palette.creamDim)
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityLabel("Comes from the Mystery Box")
    }
}

// MARK: - Shared pieces

/// "◉ 120" coin count.
struct CoinBadge: View {
    let coins: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ItemIcon(spriteID: "coin", pixel: 1.6)
            Text("\(coins)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.gold)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(Theme.Palette.ink.opacity(0.72)))
        .overlay(Capsule().strokeBorder(Theme.Palette.gold.opacity(0.35), lineWidth: 1))
        .animation(.default, value: coins)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(coins) coins")
    }
}

private struct PriceLabel: View {
    var text: String?
    let price: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let text { Text(text) }
            ItemIcon(spriteID: "coin", pixel: 1.4)
            Text("\(price)").monospacedDigit()
        }
    }
}

struct RarityTag: View {
    let rarity: Rarity

    var body: some View {
        Text(rarity.displayName.uppercased())
            .font(Theme.Typography.eyebrow)
            .tracking(1)
            .foregroundStyle(rarity.color)
    }
}

extension Rarity {
    var color: Color {
        switch self {
        case .common: return Theme.Palette.creamDim
        case .rare: return Theme.Palette.sky
        case .epic: return Color(hex: 0xB49AE0)
        case .legendary: return Theme.Palette.gold
        }
    }
}
