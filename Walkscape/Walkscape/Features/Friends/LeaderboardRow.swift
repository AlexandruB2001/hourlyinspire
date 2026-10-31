import SwiftUI
import WalkscapeDomain

struct LeaderboardRow: View {
    @Environment(AppModel.self) private var model
    let entry: LeaderboardEntry
    var compact = false

    var body: some View {
        let participant = entry.participant
        HStack(spacing: Theme.Spacing.m) {
            rankBadge
            AvatarPortrait(avatarID: participant.avatarID, outfit: model.outfit(for: participant.id), size: compact ? 28 : 36,
                           ring: participant.isCurrentUser ? Theme.Palette.gold : Theme.Palette.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(participant.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(participant.isCurrentUser ? Theme.Palette.gold : Theme.Palette.cream)
                if !compact, let title = model.titleName(for: participant.id) { TitleLabel(title: title) }
                if !compact { subtitle }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(distanceText)
                    .font(Theme.Typography.stat)
                    .foregroundStyle(participant.isPlaceable ? Theme.Palette.cream : Theme.Palette.creamDim)
                if !compact, let zoneID = participant.currentZoneID, let zone = model.engine.catalog.zone(withID: zoneID) {
                    Text(zone.name)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            }
        }
        .padding(.vertical, compact ? 2 : Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var distanceText: String {
        guard let meters = entry.participant.distanceMeters else { return "—" }
        return (entry.participant.isDistanceEstimated ? "≈" : "") + DistanceFormatting.kilometres(meters)
    }

    @ViewBuilder private var rankBadge: some View {
        let rank = entry.rank
        Text(rank.map { "\($0)" } ?? "–")
            .font(.system(.subheadline, design: .rounded).weight(.heavy).monospacedDigit())
            .foregroundStyle(rank == 1 ? Theme.Palette.ink : Theme.Palette.cream)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill(rank == 1 ? Theme.Palette.gold : Theme.Palette.forestRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
    }

    @ViewBuilder private var subtitle: some View {
        let participant = entry.participant
        switch entry.unrankedReason {
        case .noDataToday:
            Text("No update today").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.creamDim)
        case .estimatedDistance:
            Text("Estimated from steps · unranked").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.gold)
        case nil:
            if let updated = participant.updatedAt {
                Label("Updated \(RelativeTime.short(since: updated, now: model.now))",
                      systemImage: participant.availability == .stale ? "clock.badge.exclamationmark" : "clock")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(participant.availability == .stale ? Theme.Palette.ember : Theme.Palette.creamDim)
            }
        }
    }

    private var accessibilityText: String {
        let participant = entry.participant
        var parts = [participant.name]
        if let rank = entry.rank { parts.insert("Rank \(rank)", at: 0) }
        if let meters = participant.distanceMeters { parts.append("\(DistanceFormatting.kilometres(meters)) today") }
        switch entry.unrankedReason {
        case .noDataToday: parts.append("no update today")
        case .estimatedDistance: parts.append("estimated, unranked")
        case nil: if participant.availability == .stale { parts.append("data may be out of date") }
        }
        return parts.joined(separator: ", ")
    }
}
