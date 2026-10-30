import SwiftUI
import WalkscapeDomain

/// A player's title, shown under their name.
struct TitleLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Typography.micro.weight(.semibold))
            .foregroundStyle(Theme.Palette.gold)
            .lineLimit(1)
            .accessibilityLabel("Title: \(title)")
    }
}

extension View {
    /// The pixel picture frame chosen in the showcase.
    func profileFrame(_ frame: ProfileFrame, cornerRadius: CGFloat = Theme.Radius.m) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color(hex: frame.outer), lineWidth: 4)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius - 3)
                    .inset(by: 3)
                    .strokeBorder(Color(hex: frame.inner), lineWidth: 2))
        )
    }
}

/// Your walker in front of your favourite zone, inside your frame, with your companion.
struct ProfilePortrait: View {
    @Environment(AppModel.self) private var model
    let showcase: ProfileShowcase
    var width: CGFloat = 104
    var height: CGFloat = 112

    var body: some View {
        let zone = showcase.favoriteZoneID.flatMap { model.engine.catalog.zone(withID: $0) }
        ZStack(alignment: .bottom) {
            if let zone {
                PixelImageView(image: PixelArtCache.shared.thumbnail(zone.biome, width: 52, height: 56), pixel: 2)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
            }
            HStack(alignment: .bottom, spacing: 0) {
                WalkingCharacter(avatarID: model.settings.avatarID, outfit: model.outfit, walking: true, pixel: 3.5)
                if showcase.showsCompanion, let companion = model.companion {
                    PixelImageView(image: PixelArtCache.shared.companion(companion.speciesID,
                                                                        kilometres: companion.growth(lifetimeMeters: model.progression.lifetimeMeters).kilometres,
                                                                        accessories: companion.wornAccessories),
                                   pixel: 1.6)
                }
            }
            .padding(.bottom, 6)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        .profileFrame(FrameCatalog.frame(withID: showcase.frameID))
        .accessibilityHidden(true)
    }
}

/// Profile section: what you show friends, with a way into the editor.
struct ShowcaseSection: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        let showcase = model.currentShowcase
        let achievements = showcase.achievementIDs.compactMap { id in AchievementCatalog.standard.first { $0.id == id } }
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Showcase") {
                Button("Customize") { editing = true }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            }
            HStack(spacing: Theme.Spacing.m) {
                labelled("Title", TitleCatalog.title(withID: showcase.titleID)?.name ?? "—")
                labelled("Frame", FrameCatalog.frame(withID: showcase.frameID).name)
                labelled("Zone", showcase.favoriteZoneID.flatMap { model.engine.catalog.zone(withID: $0)?.name } ?? "None")
            }
            if achievements.isEmpty {
                Text("Pick up to three achievements to show off.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(achievements) { achievement in
                        VStack(spacing: 2) {
                            ItemIcon(spriteID: achievement.spriteID, pixel: 2.5)
                            Text(achievement.name)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.cream)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Text("Friends and teammates see your title and frame.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .pixelPanel()
        .sheet(isPresented: $editing) { ShowcaseEditor() }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label)
            Text(value)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.cream)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Choose a title, frame, favourite zone, companion and achievements.
struct ShowcaseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let facts = model.profileFacts
        let showcase = model.currentShowcase
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack {
                        Spacer()
                        VStack(spacing: Theme.Spacing.xs) {
                            ProfilePortrait(showcase: showcase, width: 130, height: 140)
                            Text("@\(model.settings.username)")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Palette.cream)
                            if let title = TitleCatalog.title(withID: showcase.titleID) { TitleLabel(title: title.name) }
                        }
                        Spacer()
                    }

                    group("Title") {
                        ForEach(TitleCatalog.all) { title in
                            let unlocked = title.requirement.isMet(by: facts)
                            choiceRow(name: title.name, hint: unlocked ? nil : title.requirement.hint,
                                      selected: showcase.titleID == title.id, unlocked: unlocked) {
                                model.showcase.titleID = title.id
                            }
                        }
                    }

                    group("Frame") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
                            ForEach(FrameCatalog.all) { frame in
                                let unlocked = frame.requirement.isMet(by: facts)
                                Button { model.showcase.frameID = frame.id } label: {
                                    VStack(spacing: Theme.Spacing.xs) {
                                        RoundedRectangle(cornerRadius: Theme.Radius.s)
                                            .fill(Theme.Palette.skyMuted)
                                            .frame(height: 54)
                                            .profileFrame(frame, cornerRadius: Theme.Radius.s)
                                            .overlay {
                                                if !unlocked { Image(systemName: "lock.fill").foregroundStyle(Theme.Palette.creamDim) }
                                            }
                                        Text(frame.name)
                                            .font(Theme.Typography.micro)
                                            .foregroundStyle(showcase.frameID == frame.id ? Theme.Palette.gold : Theme.Palette.cream)
                                        if !unlocked {
                                            Text(frame.requirement.hint)
                                                .font(Theme.Typography.micro)
                                                .foregroundStyle(Theme.Palette.creamDim)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(!unlocked)
                                .accessibilityLabel("\(frame.name) frame\(unlocked ? "" : ", locked. \(frame.requirement.hint)")")
                                .accessibilityAddTraits(showcase.frameID == frame.id ? .isSelected : [])
                            }
                        }
                    }

                    group("Favourite zone") {
                        choiceRow(name: "None", hint: nil, selected: showcase.favoriteZoneID == nil, unlocked: true) {
                            model.showcase.favoriteZoneID = nil
                        }
                        ForEach(model.engine.catalog.zones.filter { facts.progression.discoveredZoneIDs.contains($0.id) }) { zone in
                            choiceRow(name: zone.name, hint: nil, selected: showcase.favoriteZoneID == zone.id, unlocked: true) {
                                model.showcase.favoriteZoneID = zone.id
                            }
                        }
                        Text("Discover more zones to add them here.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }

                    group("Companion") {
                        @Bindable var model = model
                        Toggle("Show my companion", isOn: $model.showcase.showsCompanion)
                            .tint(Theme.Palette.leaf)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.cream)
                    }

                    group("Achievements (up to \(ProfileShowcase.maxAchievements))") {
                        let unlocked = AchievementCatalog.standard.filter { $0.isUnlocked(by: facts.progression) }
                        if unlocked.isEmpty {
                            Text("Unlock achievements on your walks to show them here.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.creamDim)
                        }
                        ForEach(unlocked) { achievement in
                            choiceRow(name: achievement.name, hint: nil,
                                      selected: showcase.achievementIDs.contains(achievement.id), unlocked: true) {
                                model.showcase = showcase
                                model.showcase.toggleAchievement(achievement.id)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.cream)
            content()
        }
        .pixelPanel()
    }

    private func choiceRow(name: String, hint: String?, selected: Bool, unlocked: Bool,
                           select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: selected ? "checkmark.circle.fill" : unlocked ? "circle" : "lock.fill")
                    .foregroundStyle(selected ? Theme.Palette.gold : Theme.Palette.creamDim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(Theme.Typography.caption.weight(.semibold))
                        .foregroundStyle(unlocked ? Theme.Palette.cream : Theme.Palette.creamDim)
                    if let hint {
                        Text(hint)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
