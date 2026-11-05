import SwiftUI
import WalkscapeDomain
import WidgetKit

@main
struct WalkscapeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WalkscapeComplication()
    }
}

/// Today's walk on the watch face: a ring to the next kilometre, or the
/// distance and zone. Reads Apple Health on the watch itself.
struct WalkscapeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalkscapeComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Walkscape")
        .description("Today's walk and the zone you're in.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let glance: WatchGlance
}

struct ComplicationProvider: TimelineProvider {
    static let preview = WatchGlance.make(
        snapshot: nil,
        live: DailyProgress(userID: UserID("preview"), localDate: LocalDay(date: Date(), timeZone: .current),
                            timeZoneIdentifier: TimeZone.current.identifier, steps: 5_830, distanceMeters: 4_250,
                            distanceSource: .recorded, updatedAt: Date()),
        today: LocalDay(date: Date(), timeZone: .current))

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), glance: Self.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        guard !context.isPreview else { return completion(placeholder(in: context)) }
        Task { completion(ComplicationEntry(date: Date(), glance: await Self.read(at: Date()))) }
    }

    /// Now, and a fresh start at local midnight. The Watch app also reloads
    /// these whenever it reads Apple Health.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        Task {
            let now = Date()
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            let entries = [
                ComplicationEntry(date: now, glance: await Self.read(at: now)),
                ComplicationEntry(date: midnight, glance: WatchGlance.make(snapshot: nil, live: nil,
                                                                           today: LocalDay(date: midnight, timeZone: .current))),
            ]
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    static func read(at now: Date) async -> WatchGlance {
        let today = LocalDay(date: now, timeZone: .current)
        let reading = try? await HealthKitWalkingDataProvider().fetchDailyTotals(for: today, timeZone: .current, now: now)
        let live = reading.flatMap { $0.hasAnyData ? DailyProgress(snapshot: $0, userID: UserID("watch")) : nil }
        return WatchGlance.make(snapshot: nil, live: live, today: today)
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var glance: WatchGlance { entry.glance }
    private var kilometres: String { DistanceFormatting.kilometres(glance.todayMeters) }
    /// "4.2", for the small ring.
    private var number: String { kilometres.replacingOccurrences(of: " km", with: "") }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Walkscape: \(kilometres) today, in \(glance.zone.currentZone.name)")
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: glance.kilometreFraction) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(number).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("WALKSCAPE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .widgetAccentable()
                Text("\(kilometres) today")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(glance.zone.currentZone.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                ProgressView(value: glance.zone.fractionThroughZone)
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: "figure.walk")
                .font(.title3)
                .widgetLabel {
                    Gauge(value: glance.kilometreFraction) {
                        Text("km")
                    } currentValueLabel: {
                        Text(number)
                    }
                }
        default:
            Text("\(kilometres) · \(glance.zone.currentZone.name)")
        }
    }
}
