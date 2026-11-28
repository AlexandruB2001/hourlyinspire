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
                    if let loadError = model.shop.loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.ember)
                    }
                    plusCard
                    Text("Bundles")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.cream)
                    ForEach(StoreCatalog.bundles) { BundleCard(product: $0, busy: busyProductID == $0.id) { buy($0) } }
                    PremiumLooksCard()
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
            .task { if model.shop.products.isEmpty { await model.shop.loadProducts() } }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            }
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
            Text("Extra looks and a bonus chest")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.cream)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(StoreCatalog.plusPerks, id: \.self) { perk in
                    Label(perk, systemImage: "sparkle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.cream)
                }
            }
            Text("Nothing in the game is locked behind Plus: it adds looks and a bonus chest.")
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

/// One cosmetic bundle: a large animated preview of everything inside, what's
/// included, and the price.
private struct BundleCard: View {
    @Environment(AppModel.self) private var model
    let product: StoreProduct
    let busy: Bool
    let buy: (StoreProduct) -> Void
    /// The seasonal outfits show as a mystery silhouette until tapped.
    @State private var revealed = false

    var body: some View {
        let owned = model.entitlements.bundles.contains(product.id)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            TimelineView(.periodic(from: .now, by: 1.0 / 8)) { context in
                preview(frame: Int(context.date.timeIntervalSinceReferenceDate * 8))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard kind == .outfits, !revealed else { return }
                withAnimation(.easeInOut(duration: 0.3)) { revealed = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeInOut(duration: 0.3)) { revealed = false }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(product.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    Text(product.summary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                    if !contentNames.isEmpty {
                        Text(contentNames.joined(separator: " · "))
                            .font(Theme.Typography.micro.weight(.heavy))
                            .foregroundStyle(Theme.Palette.gold)
                    }
                }
                Spacer(minLength: 0)
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
        }
        .pixelPanel()
        .accessibilityElement(children: .contain)
    }

    private enum Kind { case outfits, skins, trails, campsite }

    private var kind: Kind {
        let first = product.contents.first
        if PremiumOutfits.items.contains(where: { $0.id == first }) { return .outfits }
        if CompanionSkinCatalog.skin(withID: first) != nil { return .skins }
        if TrailEffectCatalog.effect(withID: first) != nil { return .trails }
        return .campsite
    }

    /// Everything the bundle unlocks, by name.
    private var contentNames: [String] {
        switch kind {
        case .outfits: return PremiumOutfits.items.map(\.name)
        case .skins: return CompanionSkinCatalog.all.map(\.name)
        case .trails: return TrailEffectCatalog.all.map(\.name)
        case .campsite: return CampfireCatalog.premiumDecorations.map(\.name)
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .outfits:
            if revealed {
                // One band per season: autumn, winter, spring, summer.
                LinearGradient(colors: [Color(hex: 0xE8893A), Color(hex: 0xBFE6F2), Color(hex: 0xF2B7A8), Color(hex: 0xE3B04B)],
                               startPoint: .leading, endPoint: .trailing)
            } else {
                RadialGradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x0A0A0A)], center: .center, startRadius: 10, endRadius: 180)
            }
        case .skins:
            LinearGradient(colors: [Theme.Palette.skyMuted, Theme.Palette.sky], startPoint: .top, endPoint: .bottom)
        case .trails, .campsite:
            Theme.Palette.night
        }
    }

    @ViewBuilder private func preview(frame: Int) -> some View {
        let cache = PixelArtCache.shared
        switch kind {
        case .outfits:
            // The walker wearing all four seasonal pieces at once: a white mystery
            // silhouette next to a big "?", in full colour while tapped.
            let walker = PixelImageView(image: cache.characterFrame(frame, avatarID: model.settings.avatarID,
                                                                    outfit: PremiumOutfits.items.map(\.id), walking: true), pixel: 5)
            if revealed {
                walker
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xl) {
                        walker.brightness(1)
                        PixelQuestionMark(pixel: 9)
                            .offset(y: frame / 4 % 2 == 0 ? -3 : 0)
                    }
                    Text("Tap to peek")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        case .skins:
            let species = model.companion?.speciesID ?? "emberfox"
            HStack(spacing: Theme.Spacing.l) {
                ForEach(CompanionSkinCatalog.all) { skin in
                    PixelImageView(image: cache.companion(species, kilometres: 25, skin: skin), pixel: 4)
                        .offset(y: (frame / 4 + CompanionSkinCatalog.all.firstIndex(of: skin)!) % 2 == 0 ? -2 : 0)
                }
            }
        case .trails:
            HStack(spacing: Theme.Spacing.xl) {
                ForEach(TrailEffectCatalog.all) { trail in
                    VStack(spacing: 3) {
                        ForEach(0..<6, id: \.self) { index in
                            let step = (index + frame / 2) % 6
                            Rectangle()
                                .fill(Color(hex: trail.colors[step % trail.colors.count]).opacity(1 - Double(step) / 7))
                                .frame(width: 7, height: 7)
                                .offset(x: CGFloat((step % 3) - 1) * 4)
                        }
                    }
                }
            }
        case .campsite:
            // The finished camp at night with every decoration, fire flickering.
            if let image = cache.campsite(level: CampfireCatalog.levels.last?.level ?? 5,
                                          decorations: product.contents, frame: frame / 3) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            }
        }
    }
}

/// A chunky white "?" drawn in square pixels, outlined in black.
private struct PixelQuestionMark: View {
    let pixel: CGFloat
    private static let rows = [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Rectangle().fill(cell == "#" ? Color.white : Color.clear).frame(width: pixel, height: pixel)
                    }
                }
            }
        }
        .shadow(color: .black, radius: 0, x: 2, y: 2)
        .accessibilityLabel("Mystery")
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
