import SwiftUI
import WalkscapeDomain

/// Friends' recent milestones, with a cheer for each.
struct MilestoneFeedSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Friend milestones")
            if model.milestoneFeed.isEmpty {
                Text("When friends hit a big moment (their first 10 km, a companion growing up, a new level) it shows up here so you can cheer them on.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            ForEach(model.milestoneFeed) { milestone in
                MilestoneRow(milestone: milestone)
            }
        }
        .pixelPanel()
    }
}

private struct MilestoneRow: View {
    @Environment(AppModel.self) private var model
    let milestone: FriendMilestone
    @State private var sending: Reaction?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                AvatarPortrait(avatarID: milestone.avatarID, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(milestone.text)
                        .font(Theme.Typography.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.cream)
                    Text(milestone.day.displayDate)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Reaction.allCases, id: \.self) { reaction in
                    let chosen = milestone.myReaction == reaction
                    Button {
                        sending = reaction
                        Task {
                            await model.react(to: milestone, with: reaction)
                            sending = nil
                        }
                    } label: {
                        Text(reaction.emoji)
                            .font(.system(size: 18))
                            .frame(width: 36, height: 30)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .fill(chosen ? Theme.Palette.gold.opacity(0.35) : Theme.Palette.forestRaised))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .strokeBorder(chosen ? Theme.Palette.gold : Theme.Palette.ink, lineWidth: 2))
                            .scaleEffect(sending == reaction ? 1.25 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(sending != nil)
                    .accessibilityLabel("React with \(reaction.rawValue)")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
                Spacer()
                if milestone.reactions > 0 {
                    Text("\(milestone.reactions) cheer\(milestone.reactions == 1 ? "" : "s")")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: sending)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .sensoryFeedback(.success, trigger: milestone.myReaction)
    }
}
