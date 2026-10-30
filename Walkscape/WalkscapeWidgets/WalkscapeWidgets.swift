import PixelArt
import SwiftUI
import WalkscapeDomain
import WidgetKit

@main
struct WalkscapeWidgetBundle: WidgetBundle {
    var body: some Widget {
        WalkscapeJourneyWidget()
    }
}

/// Your walker and companion on today's trail. Small: total kilometres.
/// Medium: today's distance and the next zone.
struct WalkscapeJourneyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalkscapeJourney", provider: JourneyProvider()) { entry in
            JourneyWidgetView(entry: entry)
        }
        .configurationDisplayName("Walkscape")
        .description("Your walker and companion, with how far you've walked.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct JourneyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct JourneyProvider: TimelineProvider {
    func placeholder(in context: Context) -> JourneyEntry {
        JourneyEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (JourneyEntry) -> Void) {
        completion(JourneyEntry(date: Date(), snapshot: context.isPreview ? .preview : Self.load() ?? .preview))
    }

    /// The app reloads the widget whenever its numbers change. Besides that,
    /// one entry for now and one at local midnight, when today's walk resets.
    func getTimeline(in context: Context, completion: @escaping (Timeline<JourneyEntry>) -> Void) {
        let now = Date()
        let saved = Self.load() ?? .preview
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let entries = [now, midnight].map { date in
            JourneyEntry(date: date, snapshot: saved.showing(on: LocalDay(date: date, timeZone: .current)))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60))))
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: WidgetSnapshot.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Views

private enum Palette {
    static let ink = Color(red: 0x1E / 255, green: 0x22 / 255, blue: 0x33 / 255)
    static let cream = Color(red: 0xFF / 255, green: 0xF6 / 255, blue: 0xE0 / 255)
    static let gold = Color(red: 0xE3 / 255, green: 0xB0 / 255, blue: 0x4B / 255)
    static let leaf = Color(red: 0x7D / 255, green: 0xBA / 255, blue: 0x5E / 255)
}

struct JourneyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JourneyEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var snapshot: WidgetSnapshot { entry.snapshot }

    /// Walker and companion over the scene, total distance underneath.
    private var small: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(Self.kilometres(snapshot.totalMeters))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.cream)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("WALKED IN TOTAL")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.gold)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ink.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ink, lineWidth: 2))
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            PixelScene(snapshot: snapshot, width: 64, height: 64, walkerPosition: 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walkscape: \(Self.kilometres(snapshot.totalMeters)) walked in total")
    }

    /// The scene across the whole widget: walker and companion on the left,
    /// today's walk on the right.
    private var medium: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.gold)
                Text(Self.kilometres(snapshot.todayMeters))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.cream)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let steps = snapshot.todaySteps {
                    Text("\(steps.formatted()) steps")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.cream.opacity(0.85))
                }
                Text(snapshot.zoneName)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.cream)
                    .lineLimit(1)
                ProgressCapsule(fraction: 1 - Double(snapshot.metersToNextZone) / 1_000)
                    .frame(width: 110, height: 7)
                Text("\(Self.kilometres(snapshot.metersToNextZone)) to \(snapshot.nextZoneName)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.cream.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.ink.opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ink, lineWidth: 2))
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            PixelScene(snapshot: snapshot, width: 136, height: 64, walkerPosition: 0.24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walkscape: \(Self.kilometres(snapshot.todayMeters)) today, in \(snapshot.zoneName). \(Self.kilometres(snapshot.metersToNextZone)) to \(snapshot.nextZoneName).")
    }

    static func kilometres(_ meters: Int) -> String {
        let km = Double(max(0, meters)) / 1_000
        return km >= 100 ? "\(Int(km).formatted()) km" : String(format: "%.1f km", km)
    }
}

private struct ProgressCapsule: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.cream.opacity(0.2))
                Capsule().fill(Palette.gold).frame(width: proxy.size.width * min(1, max(0.04, fraction)))
            }
        }
        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1))
    }
}

/// Today's zone with the walker and companion standing on the path, drawn
/// with the app's pixel-art renderer and scaled up without smoothing.
private struct PixelScene: View {
    let snapshot: WidgetSnapshot
    let width: Int
    let height: Int
    let walkerPosition: Double

    var body: some View {
        if let image = WidgetArt.scene(snapshot, width: width, height: height, walkerPosition: walkerPosition) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Palette.ink
        }
    }
}

enum WidgetArt {
    static func scene(_ snapshot: WidgetSnapshot, width: Int, height: Int, walkerPosition: Double) -> CGImage? {
        let layers = SceneRenderer.render(snapshot.biome, width: width, height: height)
        var canvas = layers.composite(cloudOffset: 9, farOffset: 4, midOffset: 7, groundOffset: 3)
        let walker = CharacterSprites.idleFrame(avatarID: snapshot.avatarID, outfit: snapshot.outfit)
        let walkerX = Int((Double(width) * walkerPosition).rounded())
        if let species = snapshot.companionSpeciesID {
            // Just behind the walker, as on the Journey scene.
            let companion = CompanionSprites.render(speciesID: species,
                                                    growth: CompanionGrowth(kilometres: snapshot.companionKilometres),
                                                    accessories: snapshot.companionAccessories,
                                                    skin: CompanionSkinCatalog.skin(withID: snapshot.companionSkinID))
            canvas.draw(companion, x: walkerX - CompanionSprites.canvasSize + 2, y: layers.footY - CompanionSprites.canvasSize + 1)
        }
        canvas.draw(walker, x: walkerX, y: layers.footY - walker.height + 1)
        return canvas.cgImage()
    }
}

private extension PixelCanvas {
    func cgImage() -> CGImage? {
        let data = Data(rgbaBytes) as CFData
        guard let provider = CGDataProvider(data: data), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

#Preview(as: .systemSmall) {
    WalkscapeJourneyWidget()
} timeline: {
    JourneyEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    WalkscapeJourneyWidget()
} timeline: {
    JourneyEntry(date: .now, snapshot: .preview)
}
