import SwiftUI
import WalkscapeDomain

/// Every player's walking today: the top walkers, then your own position.
struct DailyLeaderboardSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.isSignedIn {
                SignInCard()
            } else if let board = model.dailyLeaderboard {
                content(board)
            } else if let error = model.dailyLeaderboardError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            } else {
                ProgressView().tint(Theme.Palette.gold).frame(maxWidth: .infinity)
            }
        }
        .task(id: model.today) { await model.refreshDailyLeaderboard() }
    }

    private func content(_ board: DailyLeaderboard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Today's top walkers")
                if board.top.isEmpty {
                    Text("Nobody's on the board yet today. Be the first!")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                ForEach(board.top) { row in
                    DailyLeaderboardLine(row: row, detail: nil)
                    if row.id != board.top.last?.id { Divider().overlay(Theme.Palette.ink) }
                }
            }
            .pixelPanel()

            if let me = board.me {
                DailyLeaderboardLine(row: me, detail: Self.status(board.myStatus))
                    .pixelPanel(fill: Theme.Palette.forestRaised)
            }

            if !board.isShownToOthers {
                Label("You're hidden from other players. Only you can see your position.", systemImage: "eye.slash")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            if let error = model.dailyLeaderboardError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            }
            Text("Resets with each calendar day. Only distances recorded by Apple Health are ranked. Show or hide yourself in Profile.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
        }
    }

    private static func status(_ status: DailyLeaderboardStatus) -> String {
        switch status {
        case .ranked(let rank, let players): return "#\(rank) of \(players) today"
        case .notWalked: return "Walk to get on the board"
        case .estimated: return "Estimated from steps, so not ranked"
        case .underReview: return "Today's walk is being checked"
        }
    }
}

private struct DailyLeaderboardLine: View {
    let row: DailyLeaderboardRow
    /// Only your own line has one.
    let detail: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            badge
            AvatarPortrait(avatarID: row.avatarID, outfit: row.outfit, size: 40, ring: ringColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.isMe ? "\(row.username) (you)" : row.username)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(row.isMe ? Theme.Palette.gold : Theme.Palette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            }
            Spacer(minLength: 0)
            Text(DistanceFormatting.kilometres(row.meters))
                .font(Theme.Typography.stat)
                .foregroundStyle(Theme.Palette.cream)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var badge: some View {
        Text(row.rank.map { "\($0)" } ?? "–")
            .font(.system(.subheadline, design: .rounded).weight(.heavy).monospacedDigit())
            .foregroundStyle(row.rank.map { $0 <= 3 } == true ? Theme.Palette.ink : Theme.Palette.cream)
            .minimumScaleFactor(0.6)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(medalColor ?? Theme.Palette.forestRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
    }

    private var medalColor: Color? {
        switch row.rank {
        case 1: return Theme.Palette.gold
        case 2: return Color(hex: 0xD5DCE3)
        case 3: return Color(hex: 0xC48A4E)
        default: return nil
        }
    }

    private var ringColor: Color { medalColor ?? (row.isMe ? Theme.Palette.gold : Theme.Palette.ink) }

    private var accessibilityText: String {
        var parts = [row.username, "\(DistanceFormatting.kilometres(row.meters)) today"]
        if let rank = row.rank { parts.insert("Rank \(rank)", at: 0) }
        if let detail { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}

/// A one-time heads-up that your walk can now appear to every player.
struct DailyLeaderboardNotice: View {
    @Environment(AppModel.self) private var model
    @AppStorage("walkscape.dailyLeaderboardNoticeSeen") private var seen = false

    var body: some View {
        if !seen {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("New: Daily Leaderboard")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.gold)
                Text("Your username, walker and today's distance can now appear to all players. You can change this any time in Profile.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.m) {
                    Button("Got it") { seen = true }
                        .buttonStyle(.pixel)
                    Button("Hide me") {
                        model.setShowOnLeaderboard(false)
                        seen = true
                    }
                    .buttonStyle(.pixelQuiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelPanel(fill: Theme.Palette.forestRaised)
        }
    }
}
