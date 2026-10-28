import SwiftUI
import WalkscapeDomain

/// First launch: pick one of the free starter companions (and optionally
/// enter a friend's invite code).
struct CompanionOnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = CompanionCatalog.starters[0].id
    @State private var inviteCode = ""
    @State private var showingCode = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                VStack(spacing: Theme.Spacing.s) {
                    Eyebrow("Before you set off", color: Theme.Palette.gold)
                    Text("Choose Your Companion")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.Palette.cream)
                        .multilineTextAlignment(.center)
                    Text("They start out tiny. Every kilometre you walk together, they grow a little.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.creamDim)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.xl)

                ForEach(CompanionCatalog.starters) { species in
                    CompanionChoiceCard(species: species, isSelected: selection == species.id) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selection = species.id }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Button {
                        withAnimation { showingCode.toggle() }
                    } label: {
                        Label("Have an invite code from a friend?", systemImage: showingCode ? "chevron.down" : "chevron.right")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.gold)
                    }
                    if showingCode {
                        TextField("Invite code", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(Theme.Typography.headline.monospaced())
                            .padding(Theme.Spacing.m)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                            .foregroundStyle(Theme.Palette.cream)
                        Text("Your friend gets a chest once you've walked a little. The code is checked after you sign in with Apple.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    guard let species = CompanionCatalog.species(withID: selection) else { return }
                    if !inviteCode.isEmpty { model.rememberReferralCode(inviteCode) }
                    model.chooseCompanion(species)
                    if !inviteCode.isEmpty { Task { await model.refreshReferrals() } }
                } label: {
                    Text("Walk with \(CompanionCatalog.species(withID: selection)?.name ?? "them")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pixel)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .background(Theme.Palette.night.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

private struct CompanionChoiceCard: View {
    let species: CompanionSpecies
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                    PixelImageView(image: PixelArtCache.shared.companion(species.id, kilometres: 0), pixel: 4)
                }
                .frame(width: 88, height: 88)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(isSelected ? Theme.Palette.gold : Theme.Palette.ink, lineWidth: isSelected ? 3 : 2))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(species.name)
                            .font(Theme.Typography.title)
                            .foregroundStyle(isSelected ? Theme.Palette.gold : Theme.Palette.cream)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.Palette.gold)
                        }
                    }
                    Text(species.personality)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                        .multilineTextAlignment(.leading)
                    // A peek at how it grows: 5, 20 and 50 km.
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach([CompanionGrowth.Stage.sprout, .companion, .guardian], id: \.self) { stage in
                            PixelImageView(image: PixelArtCache.shared.companion(species.id, stage: stage), pixel: 1.4)
                        }
                        Text("grows as you walk")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
            }
            .pixelPanel(fill: isSelected ? Theme.Palette.forestRaised : Theme.Palette.forestDeep)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(species.name). \(species.personality)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
