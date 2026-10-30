import SwiftUI
import WalkscapeDomain

/// What to announce after a walk: new creatures or a treasure.
struct DiscoveryNews: Equatable {
    let title: String
    let subtitle: String
    let spriteID: String

    init(creatures: [Creature]) {
        let best = creatures.max { $0.rarity < $1.rarity } ?? creatures[0]
        title = creatures.count > 1 ? "\(creatures.count) new creatures!" : "New creature spotted"
        subtitle = creatures.count > 1 ? "\(best.name) and \(creatures.count - 1) more" : "\(best.name) · \(best.rarity.displayName)"
        spriteID = best.spriteID
    }

    init(treasure: Treasure) {
        title = "Treasure found!"
        subtitle = "\(treasure.name) · \(treasure.rarity.displayName)"
        spriteID = treasure.spriteID
    }
}

struct DiscoveryBanner: View {
    let news: DiscoveryNews
    let dismiss: () -> Void
    @State private var hop = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ItemIcon(spriteID: news.spriteID, pixel: 4)
                .offset(y: hop ? -4 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(news.title, color: Theme.Palette.gold)
                Text(news.subtitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text("Added to your collection")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            Spacer(minLength: 0)
        }
        .pixelPanel(fill: Theme.Palette.forestRaised, padding: Theme.Spacing.m)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .onTapGesture(perform: dismiss)
        .sensoryFeedback(.success, trigger: news)
        .task {
            withAnimation(.easeInOut(duration: 0.4).repeatCount(4, autoreverses: true)) { hop = true }
            try? await Task.sleep(for: .seconds(5))
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// World tab entry point: overall completion and a peek at the books.
struct CollectionEntryCard: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        let progress = model.collectionProgress
        let found = progress.reduce(0) { $0 + $1.found }
        let total = progress.reduce(0) { $0 + $1.total }
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Eyebrow("Collection", color: Theme.Palette.gold)
                    Spacer()
                    if !model.claimableCollectionRewards.isEmpty {
                        StatusChip(text: "Reward ready", systemImage: "gift.fill", tint: Theme.Palette.gold)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.creamDim)
                }
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(progress, id: \.category) { book in
                        VStack(spacing: 2) {
                            Text("\(book.found)")
                                .font(Theme.Typography.headline.monospacedDigit())
                                .foregroundStyle(Theme.Palette.cream)
                            Text(book.category.displayName)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.creamDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                PixelProgressBar(fraction: Double(found) / Double(max(1, total)), segments: 20, fill: Theme.Palette.leaf)
                Text("\(found) of \(total) found")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            .pixelPanel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collection, \(found) of \(total) found")
        .sheet(isPresented: $open) { CollectionView() }
    }
}

/// The collection books: relics, wildlife, postcards, treasures and memories.
struct CollectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var category: CollectionCategory = .wildlife
    @State private var rarity: Rarity?
    @State private var zoneID: String?
    @State private var claimed: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Picker("Book", selection: $category) {
                        ForEach(CollectionCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let book = model.collectionProgress.first(where: { $0.category == category }) {
                        BookHeader(book: book)
                    }
                    if !model.claimableCollectionRewards.isEmpty {
                        rewardsCard
                    }

                    switch category {
                    case .relics: relics
                    case .wildlife: wildlife
                    case .postcards: postcards
                    case .treasures: treasures
                    case .memories: memories
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: claimed)
    }

    private var rewardsCard: some View {
        let rewards = model.claimableCollectionRewards
        return HStack(spacing: Theme.Spacing.m) {
            ItemIcon(spriteID: "chest", pixel: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Collection rewards")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text("+\(rewards.reduce(0) { $0 + $1.coins }) coins · +\(rewards.reduce(0) { $0 + $1.xp }) XP for filling your books")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            Spacer(minLength: 0)
            Button("Claim") { claimed = model.claimCollectionRewards() }
                .buttonStyle(.pixel)
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }

    // MARK: Books

    private var wildlife: some View {
        let found = model.collections.wildlife
        let zones = model.engine.catalog.zones
        let creatures = WildlifeCatalog.all.filter { creature in
            (rarity == nil || creature.rarity == rarity) && (zoneID == nil || creature.zoneIDs.contains(zoneID!))
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Menu {
                    Button("All rarities") { rarity = nil }
                    ForEach(Rarity.allCases, id: \.self) { value in Button(value.displayName) { rarity = value } }
                } label: { filterLabel(rarity?.displayName ?? "All rarities") }
                Menu {
                    Button("All zones") { zoneID = nil }
                    ForEach(zones) { zone in Button(zone.name) { zoneID = zone.id } }
                } label: { filterLabel(zoneID.flatMap { id in zones.first { $0.id == id }?.name } ?? "All zones") }
            }
            grid(creatures.map { creature in
                let day = found[creature.id]
                return CollectionEntry(id: creature.id, name: day == nil ? "???" : creature.name, spriteID: creature.spriteID,
                                       rarity: creature.rarity, found: day,
                                       detail: day == nil ? "Spotted in \(zoneNames(creature.zoneIDs))." : creature.personality,
                                       place: zoneNames(creature.zoneIDs))
            })
            if creatures.isEmpty {
                Text("No creatures match these filters.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
    }

    private var relics: some View {
        let zones = model.engine.catalog.zones
        return grid(zones.compactMap { zone in
            guard let relic = zone.discovery else { return nil }
            let has = model.progression.collectedItemIDs.contains(relic.id)
            return CollectionEntry(id: relic.id, name: has ? relic.name : "???", spriteID: relic.spriteID, rarity: nil,
                                   found: nil, detail: has ? relic.detail : "Found in \(zone.name).", place: zone.name,
                                   isFound: has)
        })
    }

    private var treasures: some View {
        let found = model.collections.treasures
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Treasures hide in trail chests and weekly quest chests.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            grid(TreasureCatalog.all.map { treasure in
                let day = found[treasure.id]
                return CollectionEntry(id: treasure.id, name: day == nil ? "???" : treasure.name, spriteID: treasure.spriteID,
                                       rarity: treasure.rarity, found: day,
                                       detail: day == nil ? "A \(treasure.rarity.displayName.lowercased()) treasure." : treasure.detail,
                                       place: nil)
            })
        }
    }

    private var postcards: some View {
        let earned = Postcards.earned(in: model.progression)
        let zones = model.engine.catalog.zones
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Postcards come from returning to a place on different days.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            ForEach(PostcardCatalog.all) { postcard in
                let zone = zones.first { $0.id == postcard.zoneID }
                let day = earned[postcard.id]
                let visits = zone.map { z in model.progression.dailyBestMeters.values.filter { $0 >= z.startMeters }.count } ?? 0
                HStack(spacing: Theme.Spacing.m) {
                    ZStack {
                        if let zone {
                            PixelImageView(image: PixelArtCache.shared.thumbnail(zone.biome, width: 48, height: 32), pixel: 1.6)
                                .saturation(day == nil ? 0 : 1)
                                .opacity(day == nil ? 0.45 : 1)
                        }
                    }
                    .frame(width: 77, height: 51)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .strokeBorder(day == nil ? Theme.Palette.ink : Theme.Palette.cream, lineWidth: 3))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(postcard.title)
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundStyle(day == nil ? Theme.Palette.creamDim : Theme.Palette.cream)
                        Text(day == nil ? "Visit \(zone?.name ?? "") on \(postcard.visitsNeeded) days · \(min(visits, postcard.visitsNeeded))/\(postcard.visitsNeeded)"
                             : postcard.caption)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                        if let day {
                            Text(day.displayDate)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.gold)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .pixelPanel(padding: Theme.Spacing.s)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var memories: some View {
        let reached = MemoryCatalog.reached(in: model.progression)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(MemoryCatalog.all) { memory in
                let day = reached[memory.id]
                HStack(spacing: Theme.Spacing.m) {
                    ItemIcon(spriteID: memory.spriteID, pixel: 2.5, locked: day == nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(memory.title)
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundStyle(day == nil ? Theme.Palette.creamDim : Theme.Palette.cream)
                        Text(memory.detail)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                    Spacer()
                    if let day {
                        Text(day.displayDate)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.gold)
                    }
                }
                .pixelPanel(padding: Theme.Spacing.s)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Pieces

    private func zoneNames(_ ids: [String]) -> String {
        ids.compactMap { id in model.engine.catalog.zones.first { $0.id == id }?.name }.joined(separator: " or ")
    }

    private func filterLabel(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(text)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.cream)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(Theme.Palette.forestRaised))
    }

    private func grid(_ entries: [CollectionEntry]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
            ForEach(entries) { CollectionTile(entry: $0) }
        }
    }
}

/// Completion of the selected book.
private struct BookHeader: View {
    let book: CollectionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(book.category.displayName)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                Spacer()
                Text("\(book.found)/\(book.total) · \(book.percent)%")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.gold)
            }
            PixelProgressBar(fraction: book.fraction, segments: 16, fill: Theme.Palette.leaf)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(CollectionProgress.milestones, id: \.self) { milestone in
                    Label("\(milestone)%", systemImage: book.percent >= milestone ? "checkmark.seal.fill" : "seal")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(book.percent >= milestone ? Theme.Palette.gold : Theme.Palette.creamDim)
                }
            }
        }
        .pixelPanel()
        .accessibilityElement(children: .combine)
    }
}

struct CollectionEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let spriteID: String
    let rarity: Rarity?
    let found: LocalDay?
    let detail: String
    let place: String?
    var isFound: Bool

    init(id: String, name: String, spriteID: String, rarity: Rarity?, found: LocalDay?, detail: String, place: String?,
         isFound: Bool? = nil) {
        self.id = id
        self.name = name
        self.spriteID = spriteID
        self.rarity = rarity
        self.found = found
        self.detail = detail
        self.place = place
        self.isFound = isFound ?? (found != nil)
    }
}

private struct CollectionTile: View {
    let entry: CollectionEntry
    @State private var showsDetail = false

    var body: some View {
        Button { showsDetail = true } label: {
            VStack(spacing: Theme.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.skyMuted.opacity(entry.isFound ? 1 : 0.4))
                    ItemIcon(spriteID: entry.spriteID, pixel: 4, locked: !entry.isFound)
                }
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .strokeBorder(entry.rarity.map { $0.color.opacity(entry.isFound ? 0.9 : 0.35) } ?? Theme.Palette.ink, lineWidth: 2))
                Text(entry.name)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(entry.isFound ? Theme.Palette.cream : Theme.Palette.creamDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let rarity = entry.rarity { RarityTag(rarity: rarity) }
            }
            .pixelPanel(padding: Theme.Spacing.s)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isFound ? "\(entry.name), found" : "Not found yet. \(entry.detail)")
        .sheet(isPresented: $showsDetail) { CollectionDetail(entry: entry) }
    }
}

private struct CollectionDetail: View {
    let entry: CollectionEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                ItemIcon(spriteID: entry.spriteID, pixel: 9, locked: !entry.isFound)
            }
            .frame(width: 140, height: 140)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(entry.rarity?.color ?? Theme.Palette.ink, lineWidth: 3))
            VStack(spacing: Theme.Spacing.xs) {
                if let rarity = entry.rarity { RarityTag(rarity: rarity) }
                Text(entry.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                Text(entry.detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .multilineTextAlignment(.center)
                if let place = entry.place, entry.isFound {
                    Label(place, systemImage: "map")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                if let found = entry.found {
                    Text("Discovered \(found.displayDate)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            Button("Close") { dismiss() }
                .buttonStyle(.pixelQuiet)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.forestDeep.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
