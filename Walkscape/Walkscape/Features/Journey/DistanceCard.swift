import SwiftUI
import WalkscapeDomain

/// Today's distance and steps, and how far it is to the next zone.
struct DistanceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.zoneProgress
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Today")
                Spacer()
                if model.sync.phase == .loading {
                    ProgressView().controlSize(.mini).tint(Theme.Palette.creamDim)
                }
            }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text((model.isDistanceEstimated ? "≈ " : "") + DistanceFormatting.kilometres(model.distanceMeters))
                        .font(Theme.Typography.hero)
                        .foregroundStyle(Theme.Palette.cream)
                        .contentTransition(.numericText(value: Double(model.distanceMeters)))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(model.isDistanceEstimated ? "estimated from steps" : "walked")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(model.isDistanceEstimated ? Theme.Palette.gold : Theme.Palette.creamDim)
                }
                Spacer()
                StatBlock(value: DistanceFormatting.steps(model.steps), label: "steps", alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            PixelProgressBar(fraction: progress.fractionThroughZone)
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: progress.fractionThroughZone)

            HStack {
                Text("\(DistanceFormatting.remaining(progress.metersToNextZone)) to \(progress.nextZone.name)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.gold)
                Spacer()
                Text("km \(progress.zoneIndex) → \(progress.zoneIndex + 1)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
        .pixelPanel()
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: model.distanceMeters)
    }

    private var accessibilitySummary: String {
        let distance = DistanceFormatting.kilometres(model.distanceMeters)
        let estimated = model.isDistanceEstimated ? ", estimated from steps" : ""
        return "\(distance) walked today\(estimated), \(DistanceFormatting.steps(model.steps)) steps"
    }
}

/// Explains missing permission, missing data, errors and stale data.
struct HealthStatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label(content.title, systemImage: content.icon)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(content.tint)
                Text(content.message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.cream.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(content.actions, id: \.title) { action in
                        Button(action.title) { action.run() }
                            .buttonStyle(PixelButtonStyle(kind: action.primary ? .primary : .quiet))
                    }
                }
            }
            .pixelPanel(fill: Theme.Palette.forestRaised)
        }
    }

    private struct Content {
        struct Action {
            let title: String
            var primary = false
            let run: () -> Void
        }
        let title: String
        let message: String
        let icon: String
        var tint: Color = Theme.Palette.cream
        var actions: [Action] = []
    }

    private var content: Content? {
        let useDemo = Content.Action(title: "Use demo data") { model.switchDataSource(to: .demo) }
        let retry = Content.Action(title: "Try again", primary: true) { Task { await model.refreshWalking() } }
        if model.isDemo { return nil }
        if model.healthUnavailable {
            return Content(title: "Health data unavailable",
                           message: "This device doesn't provide Apple Health data. You can explore Walkscape with demo data instead.",
                           icon: "heart.slash", tint: Theme.Palette.ember, actions: [useDemo])
        }
        if model.needsHealthConnection {
            return Content(title: "Connect Apple Health",
                           message: "Walkscape reads only your step count and walking distance to move your character. Nothing is written to Health, and no location is used.",
                           icon: "heart.fill", tint: Theme.Palette.gold,
                           actions: [.init(title: "Connect", primary: true) { Task { await model.connectAppleHealth() } }, useDemo])
        }
        switch model.sync.phase {
        case .failed(let error):
            return Content(title: "Couldn't read Apple Health", message: message(for: error),
                           icon: "exclamationmark.triangle.fill", tint: Theme.Palette.ember, actions: [retry])
        case .noData:
            return Content(title: "No steps yet today",
                           message: "Nothing has been recorded since midnight. If you have walked, check that Walkscape can read Steps and Walking + Running Distance in Settings › Health › Data Access & Devices.",
                           icon: "shoeprints.fill", actions: [retry])
        default:
            if model.freshness == .stale, let last = model.sync.lastSuccessfulRefresh {
                return Content(title: "Data may be out of date",
                               message: "Last updated \(RelativeTime.short(since: last, now: model.now)). Your iPhone may be offline or locked.",
                               icon: "clock.badge.exclamationmark", tint: Theme.Palette.gold, actions: [retry])
            }
            return nil
        }
    }

    private func message(for error: WalkingDataError) -> String {
        switch error {
        case .healthDataUnavailable: return "Apple Health isn't available on this device."
        case .authorizationFailed(let detail), .queryFailed(let detail): return detail
        }
    }
}

/// Demo-only tools for previewing zone transitions without walking.
struct DemoControlsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Eyebrow("Demo mode", color: Theme.Palette.crystal)
            Text("These numbers are sample data. Simulate a walk to preview zone transitions.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            HStack(spacing: Theme.Spacing.s) {
                Button("+250 m") { model.simulateWalk(meters: 250) }.buttonStyle(.pixelSecondary)
                Button("+1 km") { model.simulateWalk(meters: 1_000) }.buttonStyle(.pixelSecondary)
                Button("Reset") { model.resetDemoData() }.buttonStyle(.pixelQuiet)
            }
        }
        .pixelPanel()
    }
}
