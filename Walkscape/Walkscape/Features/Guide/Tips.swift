import SwiftUI
import WalkscapeDomain

/// A short explanation shown the first time a player meets a mechanic.
/// Each is shown once; the full story is in the Walkscape Guide.
enum GameTip: String, CaseIterable, Identifiable {
    case firstChest, firstZone, companionGrowth, firstQuest, team

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstChest: return "You found a chest!"
        case .firstZone: return "A new zone"
        case .companionGrowth: return "Your companion is growing"
        case .firstQuest: return "Quests"
        case .team: return "Walking as a team"
        }
    }

    var message: String {
        let rules = CoinRules.standard
        switch self {
        case .firstChest:
            return "Chests are hidden along every kilometre you walk, \(rules.chestsPerKilometre) per kilometre. Tap the bouncing chest on the scene to open it for \(rules.coinsPerChest) coins."
        case .firstZone:
            return "Every kilometre you walk today takes you into the next zone. The first time you reach one, you find its relic."
        case .companionGrowth:
            return "Your companion grows with every kilometre you walk together, and changes shape at big milestones."
        case .firstQuest:
            return "You get new quests every day and every week. When one is done, tap Claim to collect its coins and XP."
        case .team:
            return "Every member's walking adds to the team's distance. It grows your Campfire, completes expeditions and, after the Summit Relay, opens Team Worlds."
        }
    }

    var spriteID: String {
        switch self {
        case .firstChest: return "chest"
        case .firstZone: return "map"
        case .companionGrowth: return "egg"
        case .firstQuest: return "medal"
        case .team: return "team-badge"
        }
    }

    var guideSection: GuideSection.ID {
        switch self {
        case .firstChest: return .chests
        case .firstZone: return .journey
        case .companionGrowth: return .companions
        case .firstQuest: return .quests
        case .team: return .teams
        }
    }
}

/// An inline tip card with "Got it" and a link into the guide.
struct TipCard: View {
    @Environment(AppModel.self) private var model
    let tip: GameTip
    let learnMore: (GuideSection.ID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            ItemIcon(spriteID: tip.spriteID, pixel: 3)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Eyebrow("Tip", color: Theme.Palette.gold)
                Text(tip.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                Text(tip.message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.cream.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.m) {
                    Button("Got it") { withAnimation { model.dismissTip(tip) } }
                        .buttonStyle(.pixelSecondary)
                    Button("Learn more") { learnMore(tip.guideSection) }
                        .buttonStyle(.pixelQuiet)
                }
            }
            Spacer(minLength: 0)
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}
