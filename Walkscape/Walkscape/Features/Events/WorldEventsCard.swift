import SwiftUI
import WalkscapeDomain

/// What's happening in the world today: the season and today's events.
struct WorldEventsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let events = model.todaysEvents
        let hour = Calendar.current.component(.hour, from: model.now)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "In the world today") {
                Label(model.season.displayName, systemImage: seasonIcon)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            }
            if events.isEmpty {
                Text("A quiet day on the trail. Events pop up now and then, so check back tomorrow.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            ForEach(events) { scheduled in
                let zone = model.engine.catalog.zones.first { $0.id == scheduled.zoneID }
                let found = model.hasFound(scheduled)
                HStack(spacing: Theme.Spacing.m) {
                    ItemIcon(spriteID: scheduled.event.spriteID, pixel: 3, locked: false)
                        .opacity(found ? 0.6 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(scheduled.event.name)
                                .font(Theme.Typography.caption.weight(.semibold))
                                .foregroundStyle(Theme.Palette.cream)
                            RarityTag(rarity: scheduled.event.rarity)
                        }
                        Text(status(scheduled, zoneName: zone?.name ?? "", found: found, hour: hour))
                            .font(Theme.Typography.micro)
                            .foregroundStyle(found ? Theme.Palette.leaf : Theme.Palette.creamDim)
                    }
                    Spacer(minLength: 0)
                    if found {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.Palette.leaf)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .pixelPanel()
    }

    private func status(_ scheduled: ScheduledEvent, zoneName: String, found: Bool, hour: Int) -> String {
        if found { return "Found in \(zoneName)! Recorded in your Journal." }
        let evening = { () -> Bool in
            switch scheduled.event.window {
            case .evening, .eveningIn: return true
            default: return false
            }
        }()
        if evening && hour < 17 { return "Reach \(zoneName) this evening (after 5 pm)." }
        return "Reach \(zoneName) today to find it."
    }

    private var seasonIcon: String {
        switch model.season {
        case .spring: return "camera.macro"
        case .summer: return "sun.max.fill"
        case .autumn: return "leaf.fill"
        case .winter: return "snowflake"
        }
    }
}
