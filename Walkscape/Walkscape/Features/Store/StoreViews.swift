import PixelArt
import StoreKit
import SwiftUI
import WalkscapeDomain

/// Shop tab entry to the real-money store (cosmetics only).
struct StoreEntryCard: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                ItemIcon(spriteID: "star", pixel: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(model.hasPlus ? "Walkscape Plus member" : "Walkscape Store", color: Theme.Palette.gold)
                    Text("Plus & cosmetic bundles")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    Text("Optional looks for your walker, companion and camp. The game itself is always free.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.creamDim)
            }
            .pixelPanel(fill: Theme.Palette.forestRaised)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { StoreSheet() }
    }
}

/// Walkscape Plus, cosmetic bundles, premium looks and restore.
struct StoreSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var busyProductID: String?
    @State private var message: String?
    @State private var managing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    plusCard
                    Text("Bundles")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.cream)
                    ForEach(StoreCatalog.bundles) { BundleCard(product: $0, busy: busyProductID == $0.id) { buy($0) } }
                    PremiumLooksCard()
                    if let message {
                        Text(message)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.gold)
                    }
                    Button("Restore purchases") {
                        Task { message = await model.restorePurchases() ?? "Purchases restored." }
                    }
                    .buttonStyle(.pixelQuiet)
                    legal
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Walkscape Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
            .manageSubscriptionsSheet(isPresented: $managing)
        }
        .presentationDragIndicator(.visible)
    }

    private var plusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Eyebrow("Walkscape Plus", color: Theme.Palette.gold)
                Spacer()
                if model.hasPlus {
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            Text("Extra cosmetics, every month")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.cream)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(StoreCatalog.plusPerks, id: \.self) { perk in
                    Label(perk, systemImage: "sparkle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.cream)
                }
            }
            Text("Plus is cosmetic only: no coins, XP or features are locked behind it.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
            if model.hasPlus, let until = model.entitlements.plusExpires {
                Text("Renews or ends on \(until.formatted(date: .abbreviated, time: .omitted)).")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Button("Manage subscription") { managing = true }
                    .buttonStyle(.pixelSecondary)
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(StoreCatalog.plus) { plan in
                        Button { buy(plan) } label: {
                            VStack(spacing: 2) {
                                Text(plan.id == StoreCatalog.plusYearlyID ? "Yearly" : "Monthly")
                                    .font(Theme.Typography.caption.weight(.heavy))
                                if busyProductID == plan.id {
                                    ProgressView().tint(Theme.Palette.ink)
                                } else {
                                    Text(model.shop.price(of: plan) + (plan.id == StoreCatalog.plusYearlyID ? "/yr" : "/mo"))
                                        .font(Theme.Typography.micro)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(plan.id == StoreCatalog.plusYearlyID ? PixelButtonStyle(kind: .primary) : PixelButtonStyle(kind: .secondary))
                        .disabled(busyProductID != nil)
                    }
                }
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Payment is charged to your Apple ID. Walkscape Plus renews automatically unless cancelled at least 24 hours before the end of the current period; manage or cancel it in your App Store account settings. Bundles are one-time purchases.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
            HStack(spacing: Theme.Spacing.m) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://github.com/AlexandruB2001/hourlyinspire/blob/claude/walkscape-ios-game-5jpoy4/Walkscape/docs/PRIVACY.md")!)
            }
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Palette.gold)
        }
    }

    private func buy(_ product: StoreProduct) {
        busyProductID = product.id
        message = nil
        Task {
            switch await model.buy(product) {
            case .purchased: message = "Thank you! \(product.name) is yours."
            case .pending: message = "Waiting for approval (Ask to Buy). It'll unlock once approved."
            case .cancelled: message = nil
            case .failed(let reason): message = reason
            }
            busyProductID = nil
        }
    }
}

/// One cosmetic bundle with a preview.
private struct BundleCard: View {
    @Environment(AppModel.self) private var model
    let product: StoreProduct
    let busy: Bool
    let buy: (StoreProduct) -> Void

    var body: some View {
        let owned = model.entitlements.bundles.contains(product.id)
        HStack(spacing: Theme.Spacing.m) {
            preview
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.skyMuted))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(product.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text(product.summary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                if owned {
                    Label("Owned", systemImage: "checkmark.seal.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                } else {
                    Button { buy(product) } label: {
                        if busy { ProgressView().tint(Theme.Palette.ink) } else { Text(model.shop.price(of: product)) }
                    }
                    .buttonStyle(.pixel)
                    .disabled(busy)
                }
            }
            Spacer(minLength: 0)
        }
        .pixelPanel()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var preview: some View {
        let cache = PixelArtCache.shared
        if product.contents.contains(where: { id in PremiumOutfits.items.contains { $0.id == id } }) {
            PixelImageView(image: cache.characterFrame(0, avatarID: model.settings.avatarID,
                                                       outfit: Array(product.contents.prefix(2)), walking: false), pixel: 3)
        } else if let skin = CompanionSkinCatalog.skin(withID: product.contents.first), let companion = model.companion {
            PixelImageView(image: cache.companion(companion.speciesID, kilometres: 25, skin: skin), pixel: 3.5)
        } else if let trail = TrailEffectCatalog.effect(withID: product.contents.first) {
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { index in
                    Rectangle().fill(Color(hex: trail.colors[index % trail.colors.count]).opacity(1 - Double(index) / 7))
                        .frame(width: 5, height: 5)
                }
            }
        } else {
            PixelImageView(image: cache.campsite(level: 2, decorations: product.contents, frame: 0), pixel: 0.7)
        }
    }
}

/// Choose owned skins, trails, Journal themes and premium outfit pieces.
private struct PremiumLooksCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let owned = model.entitlements
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Your premium looks")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.cream)
            picker("Companion skin", options: CompanionSkinCatalog.all.filter { owned.owns($0.id) }.map { ($0.id, $0.name) },
                   selection: $model.premiumLook.companionSkinID)
            picker("Walking trail", options: TrailEffectCatalog.all.filter { owned.owns($0.id) }.map { ($0.id, $0.name) },
                   selection: $model.premiumLook.trailEffectID)
            if model.hasPlus {
                Picker("Journal theme", selection: $model.premiumLook.journalThemeID) {
                    ForEach(JournalThemeCatalog.all) { Text($0.name).tag($0.id) }
                }
                .tint(Theme.Palette.gold)
            }
            let outfits = PremiumOutfits.items.filter { model.wallet.owns($0) }
            if !outfits.isEmpty {
                Eyebrow("Seasonal outfits")
                ForEach(outfits) { item in
                    HStack {
                        Text(item.name).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.cream)
                        Spacer()
                        Button(model.wallet.isEquipped(item) ? "Wearing" : "Wear") { model.toggleEquipped(item) }
                            .buttonStyle(PixelButtonStyle(kind: model.wallet.isEquipped(item) ? .secondary : .quiet))
                    }
                }
            }
            if owned.bundles.isEmpty && !model.hasPlus {
                Text("Looks you buy show up here.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .pixelPanel()
    }

    @ViewBuilder
    private func picker(_ title: String, options: [(String, String)], selection: Binding<String?>) -> some View {
        if !options.isEmpty {
            Picker(title, selection: selection) {
                Text("None").tag(String?.none)
                ForEach(options, id: \.0) { option in Text(option.1).tag(String?.some(option.0)) }
            }
            .tint(Theme.Palette.gold)
        }
    }
}
