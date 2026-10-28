import SwiftUI
import WalkscapeDomain

/// Browse earlier days. Read-only: looking back never re-awards anything or
/// changes today's journey.
struct DayHistoryCard: View {
    @Environment(AppModel.self) private var model
    @State private var selected: LocalDay?
    @State private var record: AppModel.DayRecord?
    @State private var isLoading = false

    var body: some View {
        let browser = DayBrowser(today: model.today, earliest: model.historyEarliestDay, selected: selected)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Eyebrow("Daily history")
            HStack(spacing: Theme.Spacing.m) {
                arrow("chevron.left", label: "Previous day", enabled: browser.canGoBack) {
                    var next = browser
                    next.goBack()
                    selected = next.selected
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(browser.isToday ? "Today" : browser.selected.weekdayName)
                        .font(Theme.Typography.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(browser.isToday ? Theme.Palette.gold : Theme.Palette.creamDim)
                    Text(browser.selected.displayDate)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                arrow("chevron.right", label: "Next day", enabled: browser.canGoForward) {
                    var next = browser
                    next.goForward()
                    selected = next.isToday ? nil : next.selected
                }
            }

            content(for: browser.selected)

            if !browser.isToday {
                Button("Back to today") { selected = nil }
                    .buttonStyle(.pixelQuiet)
            }
            Text("These are totals for this day only. Your lifetime totals are above.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim.opacity(0.85))
        }
        .pixelPanel()
        .task(id: TaskKey(day: browser.selected, todayMeters: browser.isToday ? model.distanceMeters : 0)) {
            await load(browser.selected)
        }
    }

    private struct TaskKey: Hashable {
        let day: LocalDay
        let todayMeters: Int
    }

    @ViewBuilder
    private func content(for day: LocalDay) -> some View {
        if let record, record.day == day {
            if let meters = record.meters, meters > 0 || (record.steps ?? 0) > 0 {
                let zone = model.engine.progress(forMeters: meters).currentZone
                HStack(alignment: .top) {
                    StatBlock(value: record.steps.map { $0.formatted() } ?? "–", label: "steps")
                    Spacer()
                    StatBlock(value: DistanceFormatting.kilometres(meters) + (record.isEstimated ? "*" : ""),
                              label: "distance", alignment: .center)
                    Spacer()
                    StatBlock(value: "\(meters / 1_000)", label: "km milestones", alignment: .trailing)
                }
                HStack(spacing: Theme.Spacing.s) {
                    PixelImageView(image: PixelArtCache.shared.thumbnail(zone.biome, width: 32, height: 20), pixel: 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    Text("Reached \(zone.name)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.cream)
                    Spacer()
                    Text(sourceLabel(record))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                if record.isEstimated {
                    Text("* Estimated from steps; no distance was recorded.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            } else {
                Text(emptyMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        } else {
            ProgressView()
                .tint(Theme.Palette.gold)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    private var emptyMessage: String {
        if model.isDemo { return "No demo walking recorded on this day." }
        if model.authorization != .requested { return "Connect Apple Health to see your walking history." }
        return "No walking recorded on this day."
    }

    private func sourceLabel(_ record: AppModel.DayRecord) -> String {
        if model.isDemo { return "Demo data" }
        return record.fromHealth ? "From Apple Health" : "Saved by Walkscape"
    }

    private func arrow(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.heavy))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(PixelButtonStyle(kind: enabled ? .secondary : .quiet))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func load(_ day: LocalDay) async {
        isLoading = true
        defer { isLoading = false }
        let result = await model.dayRecord(for: day)
        if result.day == (selected ?? model.today) { record = result }
    }
}
