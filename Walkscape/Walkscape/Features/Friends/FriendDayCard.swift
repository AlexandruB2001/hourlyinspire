import SwiftUI
import WalkscapeDomain

/// Tap a walker on the Journey leaderboard: a small card with their day so far.
struct FriendDayCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let participant: TrackParticipant

    var body: some View {
        let entries = Leaderboard.rank(model.trackParticipants)
        let entry = entries.first { $0.participant.id == participant.id }
        // Re-read so the card stays live while it's open.
        let current = entry?.participant ?? participant
        let zone = current.currentZoneID.flatMap { model.engine.catalog.zone(withID: $0) }

        VStack(spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                    WalkingCharacter(avatarID: current.avatarID, outfit: model.outfit(for: current.id),
                                     walking: (current.distanceMeters ?? 0) > 0, pixel: 4)
                }
                .frame(width: 84, height: 100)
                .profileFrame(model.frame(for: current.id))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Eyebrow(rankText(entry), color: entry?.rank == 1 ? Theme.Palette.gold : Theme.Palette.creamDim)
                    Text(current.isCurrentUser ? "You" : "@\(current.name)")
                        .font(Theme.Typography.title)
                        .foregroundStyle(current.isCurrentUser ? Theme.Palette.gold : Theme.Palette.cream)
                    if let title = model.titleName(for: current.id) { TitleLabel(title: title) }
                    if isTeammate(current) {
                        Label("Teammate", systemImage: "flag.fill")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.leaf)
                    }
                    Text(updatedText(current))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Theme.Spacing.m) {
                stat(current.distanceMeters.map { (current.isDistanceEstimated ? "≈" : "") + DistanceFormatting.kilometres($0) } ?? "—",
                     "walked today")
                stat(steps(for: current).map { DistanceFormatting.steps($0) } ?? "—", "steps")
            }

            if let zone {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Eyebrow("Wandering through")
                    Text(zone.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    Text(zone.tagline)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pixelPanel(fill: Theme.Palette.forestRaised, padding: Theme.Spacing.m)
            }

            if !current.isCurrentUser, let comparison = comparisonText(current) {
                Text(comparison)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Theme.Spacing.m) {
                Button("See on the track") {
                    model.trackFocus.focus(on: current.id, currentUserID: model.currentUserID)
                    model.selectedTab = .friends
                    dismiss()
                }
                .buttonStyle(.pixel)
                Button("Close") { dismiss() }
                    .buttonStyle(.pixelQuiet)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.forestDeep.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        StatBlock(value: value, label: label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelPanel(padding: Theme.Spacing.m)
    }

    private func rankText(_ entry: LeaderboardEntry?) -> String {
        guard let entry else { return "Today" }
        if let rank = entry.rank { return rank == 1 ? "Leading today" : "#\(rank) today" }
        switch entry.unrankedReason {
        case .estimatedDistance: return "Estimated · unranked"
        default: return "No update today"
        }
    }

    private func steps(for participant: TrackParticipant) -> Int? {
        if participant.isCurrentUser { return model.todayProgress?.steps }
        guard participant.availability != .unavailable else { return nil }
        return model.friends.first { $0.userID == participant.id }?.dailySteps
    }

    private func updatedText(_ participant: TrackParticipant) -> String {
        guard participant.availability != .unavailable, let updated = participant.updatedAt else {
            return "Hasn't shared a walk today yet"
        }
        let age = RelativeTime.short(since: updated, now: model.now)
        return participant.availability == .stale ? "Last update \(age), may be behind" : "Updated \(age)"
    }

    private func isTeammate(_ participant: TrackParticipant) -> Bool {
        guard !participant.isCurrentUser, let team = model.team else { return false }
        return team.members.contains { $0.id == participant.id }
    }

    private func comparisonText(_ friend: TrackParticipant) -> String? {
        guard let theirs = friend.distanceMeters, let mine = model.me.distanceMeters else { return nil }
        let gap = theirs - mine
        if abs(gap) < 50 { return "You're neck and neck. Race you to the next zone!" }
        let km = DistanceFormatting.kilometres(abs(gap))
        return gap > 0 ? "They're \(km) ahead of you today." : "You're \(km) ahead of them today."
    }
}
