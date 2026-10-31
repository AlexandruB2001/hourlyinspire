import SwiftUI
import WalkscapeDomain

/// Your companion and how close it is to growing. Tap for its evolutions,
/// your other companions and adoption.
struct CompanionCard: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        if let companion = model.companion, let species = companion.species, let growth = model.companionGrowth {
            Button { open = true } label: { card(companion, species: species, growth: growth) }
                .buttonStyle(.plain)
                .accessibilityHint("Shows its evolutions and your other companions")
                .sheet(isPresented: $open) { CompanionSheet() }
        }
    }

    private func card(_ companion: CompanionState, species: CompanionSpecies, growth: CompanionGrowth) -> some View {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                    PixelImageView(image: PixelArtCache.shared.companion(species.id, kilometres: growth.kilometres,
                                                                        accessories: companion.wornAccessories,
                                                                        skin: model.companionSkin), pixel: 3.4)
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
                Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.creamDim)
            }
            .pixelPanel()
            .accessibilityElement(children: .combine)
    }
}

/// Your companion up close: its evolutions, your other companions (swap
/// freely) and new species to adopt.
struct CompanionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adopting: CompanionSpecies?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let companion = model.companion, let species = companion.species, let growth = model.companionGrowth {
                        header(companion, species: species, growth: growth)
                        evolutions(species: species, growth: growth, accessories: companion.wornAccessories)
                        team(active: companion)
                        adoption(active: companion)
                    }
                    if let message {
                        Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ember)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Companions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
            .confirmationDialog("Adopt \(adopting?.name ?? "")?", isPresented: Binding(
                get: { adopting != nil }, set: { if !$0 { adopting = nil } }), titleVisibility: .visible) {
                Button("Adopt for \(CompanionRoster.adoptionCost) coins") {
                    guard let species = adopting else { return }
                    Task { message = await model.adoptCompanion(species) }
                }
            } message: {
                Text("\(CompanionRoster.adoptionCost) coins from your \(model.wallet.coins). It starts as a hatchling and walks with you; your current companion rests and keeps its growth.")
            }
        }
    }

    private func header(_ companion: CompanionState, species: CompanionSpecies, growth: CompanionGrowth) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            companionImage(species.id, kilometres: growth.kilometres, accessories: companion.wornAccessories, size: 96, pixel: 4.4)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Eyebrow(growth.stage.name, color: Theme.Palette.gold)
                Text(species.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                Text(species.tagline)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                Text(species.personality)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.cream.opacity(0.9))
                Text("\(growth.kilometres) km walked together since \(companion.adoptedOn.isoString)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }

    /// Every stage, reached ones in colour, the rest as silhouettes.
    private func evolutions(species: CompanionSpecies, growth: CompanionGrowth, accessories: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Evolutions")
            Text(species.growthHint)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    ForEach(CompanionGrowth.Stage.allCases, id: \.self) { stage in
                        let reached = growth.stage >= stage
                        VStack(spacing: Theme.Spacing.xs) {
                            companionImage(species.id, kilometres: stage.startKilometres, accessories: [], size: 64, pixel: 2.8)
                                .colorMultiply(reached ? .white : .black)
                                .opacity(reached ? 1 : 0.45)
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                                    .strokeBorder(stage == growth.stage ? Theme.Palette.gold : .clear, lineWidth: 3))
                            Text(stage.name)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(reached ? Theme.Palette.cream : Theme.Palette.creamDim)
                            Text(stage.startKilometres == 0 ? "Start" : "\(stage.startKilometres) km")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(reached ? Theme.Palette.gold : Theme.Palette.creamDim)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stage.name), \(stage.startKilometres) kilometres, \(reached ? "reached" : "not reached yet")")
                    }
                }
            }
            if let left = growth.kilometresToNextStage, let next = growth.stage.next {
                Text("\(left) km more together until it becomes a \(next.name).")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            }
        }
        .pixelPanel()
    }

    /// The companion walking now and any resting at camp.
    @ViewBuilder private func team(active: CompanionState) -> some View {
        let resting = model.companionRoster.resting
        if !resting.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: "Your companions")
                Text("Swap any time. Resting companions keep their growth and grow again when they walk with you.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                ForEach(resting, id: \.state.speciesID) { entry in
                    if let species = entry.state.species {
                        HStack(spacing: Theme.Spacing.m) {
                            companionImage(species.id, kilometres: entry.growth.kilometres, accessories: entry.state.wornAccessories,
                                           size: 56, pixel: 2.4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(species.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Palette.cream)
                                Text("\(entry.growth.stage.name) · \(entry.growth.kilometres) km · resting")
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Palette.creamDim)
                            }
                            Spacer(minLength: 0)
                            Button("Walk together") { model.swapCompanion(to: species.id) }
                                .buttonStyle(.pixelSecondary)
                        }
                    }
                }
            }
            .pixelPanel()
        }
    }

    /// Species not owned yet.
    @ViewBuilder private func adoption(active: CompanionState) -> some View {
        let adoptable = model.companionRoster.adoptable(active: active)
        if !adoptable.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: "Adopt a companion")
                CreationCostRow(cost: CompanionRoster.adoptionCost, balance: model.wallet.coins)
                ForEach(adoptable) { species in
                    HStack(spacing: Theme.Spacing.m) {
                        companionImage(species.id, kilometres: 0, accessories: [], size: 56, pixel: 2.4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(species.name)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Palette.cream)
                            Text(species.tagline)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.creamDim)
                        }
                        Spacer(minLength: 0)
                        let affordable = model.wallet.coins >= CompanionRoster.adoptionCost
                        Button { adopting = species } label: { CoinPriceLabel(text: "Adopt", price: CompanionRoster.adoptionCost) }
                            .buttonStyle(.pixel)
                            .disabled(!affordable)
                            .opacity(affordable ? 1 : 0.5)
                    }
                }
            }
            .pixelPanel()
        }
    }

    private func companionImage(_ speciesID: String, kilometres: Int, accessories: [String], size: CGFloat, pixel: CGFloat)
        -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.skyMuted)
            PixelImageView(image: PixelArtCache.shared.companion(speciesID, kilometres: kilometres, accessories: accessories,
                                                                skin: speciesID == model.companion?.speciesID ? model.companionSkin : nil),
                           pixel: pixel)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
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
        .pixelPanel(fill: Color(hex: JournalThemeCatalog.theme(withID: model.currentLook.journalThemeID).fill))
        .overlay(alignment: .topLeading) {
            // Plus Journal themes add an accent line along the top.
            if JournalThemeCatalog.isPlus(model.currentLook.journalThemeID) {
                Rectangle()
                    .fill(Color(hex: JournalThemeCatalog.theme(withID: model.currentLook.journalThemeID).accent))
                    .frame(height: 3)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, 2)
            }
        }
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
