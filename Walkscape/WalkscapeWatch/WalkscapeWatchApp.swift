import SwiftUI
import WalkscapeDomain

@main
struct WalkscapeWatchApp: App {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

enum WatchPalette {
    static let ink = Color(red: 0x1E / 255, green: 0x22 / 255, blue: 0x33 / 255)
    static let cream = Color(red: 0xFF / 255, green: 0xF6 / 255, blue: 0xE0 / 255)
    static let gold = Color(red: 0xE3 / 255, green: 0xB0 / 255, blue: 0x4B / 255)
    static let leaf = Color(red: 0x7D / 255, green: 0xBA / 255, blue: 0x5E / 255)
}

/// Your walker on today's zone, today's distance and steps, and how far to the next zone.
struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        let glance = model.glance
        ScrollView {
            VStack(spacing: 8) {
                WatchScene(frames: model.frames)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WatchPalette.ink, lineWidth: 2))

                VStack(spacing: 0) {
                    Text(DistanceFormatting.kilometres(glance.todayMeters) + (glance.isEstimated ? "*" : ""))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WatchPalette.gold)
                    Text(glance.todaySteps.map { "today · \(DistanceFormatting.steps($0)) steps" } ?? "today")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchPalette.cream.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(glance.zone.currentZone.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchPalette.cream)
                    ProgressView(value: glance.zone.fractionThroughZone)
                        .tint(WatchPalette.gold)
                    Text("\(DistanceFormatting.remaining(glance.zone.metersToNextZone)) to \(glance.zone.nextZone.name)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchPalette.cream.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(WatchPalette.ink.opacity(0.7)))

                if let total = glance.totalMeters {
                    Text("\(DistanceFormatting.kilometres(total)) walked in total")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchPalette.leaf)
                }

                if model.needsHealth {
                    Button("Allow Apple Health") { Task { await model.connectHealth() } }
                        .tint(WatchPalette.gold)
                    Text("So your Watch can count today's walk, even without your iPhone.")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.cream.opacity(0.7))
                        .multilineTextAlignment(.center)
                } else if model.healthUnavailable {
                    Text("Apple Health isn't available on this Watch.")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.cream.opacity(0.7))
                }
                if !model.hasPhoneData {
                    Text("Open Walkscape on your iPhone to bring over your walker's outfit and companion.")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.cream.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(WatchPalette.ink.gradient, for: .navigation)
        .task {
            await model.refresh()
            // Keeps the numbers moving while the app stays open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await model.refresh()
            }
        }
    }
}

/// The scene, stepping through the walk frames.
private struct WatchScene: View {
    let frames: [CGImage]
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            let index = frames.count > 1 && !isLuminanceReduced
                ? Int(context.date.timeIntervalSinceReferenceDate / 0.15) % frames.count : 0
            if frames.indices.contains(index) {
                Image(decorative: frames[index], scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                WatchPalette.ink
            }
        }
        .accessibilityHidden(true)
    }
}
