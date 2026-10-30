import SwiftUI
import WalkscapeDomain

/// Compact shared track plus the top of today's leaderboard, on the Journey screen.
struct FriendsPreviewCard: View {
    @Environment(AppModel.self) private var model
    @State private var selected: TrackParticipant?

    var body: some View {
        let entries = Leaderboard.rank(model.trackParticipants)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Friends today") {
                Button("Open track") { model.selectedTab = .friends }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            }
            if model.friends.isEmpty && !model.isLoadingFriends {
                Text("Add friends to walk together. Everyone appears on a shared track by distance walked today.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                FriendTrackView(style: .compact)
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(entries.prefix(3)) { entry in
                        Button { selected = entry.participant } label: {
                            HStack(spacing: Theme.Spacing.s) {
                                LeaderboardRow(entry: entry, compact: true)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.Palette.creamDim)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows their day so far")
                    }
                }
            }
        }
        .pixelPanel()
        .sheet(item: $selected) { FriendDayCard(participant: $0) }
    }
}
