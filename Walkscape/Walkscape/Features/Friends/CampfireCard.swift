import PixelArt
import SwiftUI
import WalkscapeDomain

/// The team's campsite: everyone builds it together by walking.
struct CampfireCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let campsite: Campsite
    let teamName: String
    @State private var decorating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Team campfire · level \(campsite.level.level)", color: Theme.Palette.gold)
                Spacer()
                Button("Decorate") { decorating = true }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            }
            TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.25)) { context in
                let frame = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate * 4) % 3
                PixelImageView(image: PixelArtCache.shared.campsite(level: campsite.level.level,
                                                                   decorations: campsite.decorations, frame: frame),
                               pixel: 2.6)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: CGFloat(CampfireRenderer.height) * 2.6)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.ink, lineWidth: 2))
            .accessibilityLabel("\(teamName)'s campsite: \(campsite.level.name)")

            Text(campsite.level.name)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.cream)
            Text(campsite.level.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            if let next = campsite.nextLevel {
                PixelProgressBar(fraction: campsite.fractionToNext, segments: 14, fill: Theme.Palette.ember)
                Text(nextText(next))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                Text("Your headquarters is complete. Legendary!")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.gold)
            }
            if !model.teamContributions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Eyebrow("Built by")
                    ForEach(model.teamContributions.prefix(5)) { person in
                        HStack(spacing: Theme.Spacing.s) {
                            AvatarPortrait(avatarID: person.avatarID, outfit: model.outfit(for: person.userID), size: 22)
                            Text("@\(person.username)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(person.isMember ? Theme.Palette.cream : Theme.Palette.creamDim)
                            if !person.isMember {
                                Text("former member")
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Palette.creamDim)
                            }
                            Spacer()
                            Text(DistanceFormatting.kilometres(person.meters))
                                .font(Theme.Typography.caption.monospacedDigit())
                                .foregroundStyle(Theme.Palette.creamDim)
                        }
                    }
                }
            }
            Text("Every member's walking counts, and it never goes backwards, even if someone leaves.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim.opacity(0.85))
        }
        .pixelPanel()
        .sheet(isPresented: $decorating) { DecorateSheet(campsite: campsite) }
    }

    private func nextText(_ next: CampfireLevel) -> String {
        let metersLeft = max(0, next.meters - campsite.teamMeters)
        let expeditionsLeft = max(0, next.expeditions - campsite.expeditions)
        var parts: [String] = []
        if metersLeft > 0 { parts.append("\(DistanceFormatting.kilometres(metersLeft)) more as a team") }
        if expeditionsLeft > 0 { parts.append("\(expeditionsLeft) more expedition\(expeditionsLeft == 1 ? "" : "s")") }
        return parts.isEmpty ? "Almost there!" : "Level \(next.level), \(next.name): \(parts.joined(separator: " and "))"
    }
}

/// Choose which unlocked decorations are placed (shared with the whole team).
private struct DecorateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let campsite: Campsite
    @State private var placed: [String] = []
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    PixelImageView(image: PixelArtCache.shared.campsite(level: campsite.level.level, decorations: placed, frame: 0),
                                   pixel: 2.6)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                    Text("Pick up to \(CampfireCatalog.maxPlaced). Everyone in the team sees the same campsite.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(CampfireCatalog.decorations.filter { StoreFeature.shows($0) }) { decoration in
                            let unlocked = decoration.unlockLevel <= campsite.level.level && owns(decoration)
                            let selected = placed.contains(decoration.id)
                            Button {
                                if selected { placed.removeAll { $0 == decoration.id } }
                                else if placed.count < CampfireCatalog.maxPlaced { placed.append(decoration.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selected ? "checkmark.square.fill" : unlocked ? "square" : "lock.fill")
                                        .foregroundStyle(selected ? Theme.Palette.gold : Theme.Palette.creamDim)
                                    Text(decoration.name)
                                        .font(Theme.Typography.caption.weight(.semibold))
                                        .foregroundStyle(unlocked ? Theme.Palette.cream : Theme.Palette.creamDim)
                                    Spacer()
                                    if !unlocked {
                                        Text(lockText(decoration))
                                            .font(Theme.Typography.micro)
                                            .foregroundStyle(Theme.Palette.creamDim)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!unlocked)
                        }
                    }
                    .pixelPanel()
                    if let error {
                        Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ember)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Decorate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.Palette.creamDim) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saving = true
                        Task {
                            error = await model.setCampsiteDecorations(placed)
                            saving = false
                            if error == nil { dismiss() }
                        }
                    }
                    .foregroundStyle(Theme.Palette.gold)
                    .disabled(saving)
                }
            }
        }
        .onAppear { placed = campsite.decorations }
    }

    private func owns(_ decoration: CampsiteDecoration) -> Bool {
        switch decoration.source {
        case .campfire: return true
        case .bundle: return model.entitlements.owns(decoration.id)
        case .plus: return model.hasPlus
        }
    }

    private func lockText(_ decoration: CampsiteDecoration) -> String {
        switch decoration.source {
        case .campfire: return "Campfire level \(decoration.unlockLevel)"
        case .bundle: return "Cozy Campsite Decor"
        case .plus: return "Walkscape Plus"
        }
    }
}
