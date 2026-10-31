import SwiftUI
import WalkscapeDomain

/// Spend coins from walking on Mystery Boxes: the only way to get outfits
/// for your walker and accessories for your companion.
struct ShopView: View {
    @Environment(AppModel.self) private var model
    /// Nil shows every slot.
    @State private var slot: EquipmentSlot?
    @State private var revealed: MysteryBoxPrize?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    WardrobeHeader()
                    if StoreFeature.isEnabled { StoreEntryCard() }
                    MysteryBoxCard { revealed = $0 }
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
            .sheet(item: $revealed) { MysteryRevealSheet(prize: $0) }
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
                Text("Earn \(rules.coinsPerKilometre) coins every kilometre. Chests on the trail hold \(rules.coinsPerChest) more.")
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
    let onReveal: (MysteryBoxPrize) -> Void
    @State private var opening = false
    @State private var problem: String?

    var body: some View {
        let price = ShopCatalog.mysteryBoxPrice
        let soldOut = MysteryBox.prizes(on: model.today).allSatisfy { model.wallet.owns(itemID: $0.id) }
        let odds = Rarity.allCases.map { "\($0.mysteryBoxWeight)% \($0.rawValue)" }.joined(separator: " · ")
        HStack(spacing: Theme.Spacing.m) {
            ItemIcon(spriteID: "mystery-box", pixel: 5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Mystery Box")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text(soldOut ? "You own everything. Amazing!"
                     : "The only way to get new looks: a random outfit piece or companion accessory you don't own yet.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Text(odds)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim.opacity(0.8))
                Button {
                    opening = true
                    problem = nil
                    Task {
                        let result = await model.openMysteryBox()
                        opening = false
                        switch result {
                        case .won(let prize): onReveal(prize)
                        case .notEnoughCoins(let needed): problem = "You need \(needed) more coins."
                        case .soldOut: problem = "You own everything. Amazing!"
                        case .unavailable(let message): problem = message
                        }
                    }
                } label: {
                    if opening {
                        ProgressView().tint(Theme.Palette.ink)
                    } else {
                        PriceLabel(text: "Open for", price: price)
                    }
                }
                .buttonStyle(.pixel)
                .disabled(opening || soldOut || model.wallet.coins < price)
                .opacity(soldOut || model.wallet.coins < price ? 0.5 : 1)
                .padding(.top, Theme.Spacing.xs)
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
                PixelImageView(image: PixelArtCache.shared.characterFrame(0, avatarID: model.settings.avatarID,
                                                                          outfit: [item.id], walking: false),
                               pixel: 3)
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
    @State private var shown = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Eyebrow("\(prize.rarity.displayName) find!", color: prize.rarity.color)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                PixelImageView(image: image, pixel: 6)
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
