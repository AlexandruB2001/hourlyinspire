import SwiftUI
import WalkscapeDomain

/// Teams dashboard entry: the next 5 km stop, today's stop challenge and the map.
struct TeamMapCard: View {
    @Environment(AppModel.self) private var model
    let dashboard: TeamDashboard
    @State private var open = false

    var body: some View {
        let total = dashboard.team.totalMeters
        let stop = TeamMap.reachedWaypoint(teamMeters: total)
        let toNext = (stop + 1) * TeamMap.waypointMeters - total
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Eyebrow("Team map", color: Theme.Palette.gold)
                Spacer()
                Text("Stop \(stop) of \(TeamMap.waypointCount)")
                    .font(Theme.Typography.micro.monospacedDigit())
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            if stop < TeamMap.waypointCount {
                Text("\(DistanceFormatting.kilometres(toNext)) as a team to stop \(stop + 1)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.cream)
                PixelProgressBar(fraction: 1 - Double(toNext) / Double(TeamMap.waypointMeters), segments: 14, fill: Theme.Palette.gold)
            }
            if let challenge = model.waypointChallenge(for: dashboard) {
                WaypointChallengeRow(challenge: challenge, dashboard: dashboard)
            } else {
                Text("Every 5 km the team walks together reaches a new stop, with a challenge for the day.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            Button { open = true } label: {
                Label("Open the team map", systemImage: "map.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pixel)
        }
        .pixelPanel()
        .fullScreenCover(isPresented: $open) { TeamMapView(dashboard: dashboard) }
    }
}

/// Today's challenge at the latest stop, with progress.
struct WaypointChallengeRow: View {
    @Environment(AppModel.self) private var model
    let challenge: WaypointChallenge
    let dashboard: TeamDashboard

    var body: some View {
        let today = dashboard.members.map(\.dayMeters)
        let (done, goal) = challenge.progress(todayMeters: today)
        let claimed = model.ledger.hasClaimed(challenge.reward.id)
        let walkedToday = (dashboard.members.first(where: \.isCurrentUser)?.dayMeters ?? 0) >= WaypointChallenge.participationMeters
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                ItemIcon(spriteID: "flag", pixel: 2)
                Text("Stop \(challenge.waypoint) challenge")
                    .font(Theme.Typography.caption.weight(.heavy))
                    .foregroundStyle(Theme.Palette.gold)
            }
            Text(challenge.title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.cream)
            if claimed {
                Label("Done! +\(challenge.reward.coins) coins", systemImage: "checkmark.seal.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            } else {
                PixelProgressBar(fraction: Double(done) / Double(max(1, goal)), segments: 12, fill: Theme.Palette.leaf)
                Text(progressText(done: done, goal: goal) + (walkedToday ? "" : " · walk 1 km today to share the reward"))
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised, padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private func progressText(done: Int, goal: Int) -> String {
        switch challenge.kind {
        case .push: return "\(DistanceFormatting.kilometres(done)) of \(DistanceFormatting.kilometres(goal)) today"
        case .together, .everyone: return "\(done) of \(goal) walkers so far"
        }
    }
}

// MARK: - The map

/// The whole team route as a winding trail climbing up the screen: a stop
/// every 5 km, landmarks, the team world regions, and the team at its spot.
struct TeamMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dashboard: TeamDashboard

    private static let rowHeight: CGFloat = 76

    var body: some View {
        let reached = TeamMap.reachedWaypoint(teamMeters: dashboard.team.totalMeters)
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach((0...TeamMap.waypointCount).reversed(), id: \.self) { index in
                                MapStopRow(index: index, reached: reached, width: geometry.size.width,
                                           height: Self.rowHeight, dashboard: dashboard)
                                    .id(index)
                            }
                        }
                    }
                    .task { proxy.scrollTo(reached, anchor: .center) }
                    .overlay(alignment: .bottomTrailing) {
                        Button { withAnimation { proxy.scrollTo(reached, anchor: .center) } } label: {
                            Label("Our team", systemImage: "flag.fill")
                        }
                        .buttonStyle(.pixel)
                        .padding(Theme.Spacing.l)
                    }
                }
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle(dashboard.team.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(DistanceFormatting.kilometres(dashboard.team.totalMeters) + " together")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
        }
    }
}

/// One 5 km stop, with half of the trail to the stops above and below it.
private struct MapStopRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let reached: Int
    let width: CGFloat
    let height: CGFloat
    let dashboard: TeamDashboard

    /// Horizontal position of a stop: a gentle winding curve.
    private func x(_ stop: Int) -> CGFloat {
        width / 2 + sin(Double(stop) * 0.55) * width * 0.28
    }

    var body: some View {
        let landmarks = TeamMap.landmarks(atWaypoint: index)
        let world = TeamMap.world(atWaypoint: index)
        let here = x(index)
        let labelOnLeft = here > width / 2
        ZStack(alignment: .topLeading) {
            regionColor(world)
            // Ground texture: a scatter of light and dark speckles.
            Canvas { context, size in
                for k in 0..<18 {
                    let rect = CGRect(x: rand(100 + k) * size.width, y: rand(200 + k) * size.height, width: 3, height: 3)
                    context.fill(Path(rect), with: .color(k % 2 == 0 ? .white.opacity(0.07) : .black.opacity(0.1)))
                }
            }
            scenery(world: world, pathX: here)
            // The trail: half a segment up to the stop above, half down to the one below.
            Canvas { context, _ in
                var path = Path()
                if index < TeamMap.waypointCount { path.move(to: CGPoint(x: (here + x(index + 1)) / 2, y: 0)) } else {
                    path.move(to: CGPoint(x: here, y: height / 2))
                }
                path.addLine(to: CGPoint(x: here, y: height / 2))
                if index > 0 { path.addLine(to: CGPoint(x: (here + x(index - 1)) / 2, y: height)) }
                let done = index <= reached
                let round = StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                context.stroke(path, with: .color(Theme.Palette.ink.opacity(0.85)), style: round)
                context.stroke(path, with: .color(done ? Color(hex: 0xD9B77A) : Color(hex: 0x8C7A62)),
                               style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                // Footsteps along the walked trail, faint marks ahead.
                context.stroke(path, with: .color(done ? Theme.Palette.gold : Theme.Palette.cream.opacity(0.3)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
            }
            stop(isLandmark: !landmarks.isEmpty, landmark: landmarks.first)
                .position(x: here, y: height / 2)
            if index >= 1 && model.ledger.hasClaimed("waypoint-\(index)") {
                ItemIcon(spriteID: "star", pixel: 1.6)
                    .position(x: here, y: height / 2 + (landmarks.isEmpty ? 19 : 25))
            }
            if let first = landmarks.first {
                Text(first.title)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.cream)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.Palette.ink.opacity(0.7)))
                    .lineLimit(1)
                    .frame(maxWidth: width * 0.42, alignment: labelOnLeft ? .trailing : .leading)
                    .position(x: labelOnLeft ? here - width * 0.25 : here + width * 0.25, y: height / 2)
            } else if index % 5 == 0 {
                Text(DistanceFormatting.kilometres(index * TeamMap.waypointMeters))
                    .font(Theme.Typography.micro.monospacedDigit())
                    .foregroundStyle(Theme.Palette.cream.opacity(0.7))
                    .position(x: labelOnLeft ? here - 44 : here + 44, y: height / 2)
            }
            if index == reached { team.position(x: labelOnLeft ? here - width * 0.24 : here + width * 0.24, y: height / 2 - 6) }
            if let world, TeamWorldCatalog.startMeters(of: world) / TeamMap.waypointMeters == index {
                Text(world.name.uppercased())
                    .font(Theme.Typography.eyebrow)
                    .tracking(2)
                    .foregroundStyle(Theme.Palette.gold)
                    .position(x: width / 2, y: 10)
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(landmarks))
    }

    private func stop(isLandmark: Bool, landmark: TeamMap.Landmark?) -> some View {
        let done = index <= reached
        let size: CGFloat = isLandmark ? 42 : (index == reached ? 34 : 28)
        let face = done ? Theme.Palette.gold : Color(hex: 0x5B6B62)
        return ZStack {
            // A raised button: dark base below, a lit face, a shine on top.
            Circle().fill(Theme.Palette.ink).offset(y: 3)
            Circle().fill(face)
            Circle().fill(Color.white.opacity(done ? 0.35 : 0.15))
                .frame(width: size * 0.42, height: size * 0.3)
                .offset(x: -size * 0.14, y: -size * 0.2)
            Circle().strokeBorder(Theme.Palette.ink, lineWidth: 3)
            if let landmark {
                ItemIcon(spriteID: landmark.spriteID, pixel: 2.2)
                    .opacity(done ? 1 : 0.55)
            } else if index == reached {
                ItemIcon(spriteID: "flag", pixel: 1.8)
            } else {
                Text("\(index)")
                    .font(.system(size: index >= 100 ? 9 : 11, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(done ? Theme.Palette.ink : Theme.Palette.cream.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: index == reached ? Theme.Palette.gold.opacity(0.8) : .clear, radius: 8)
    }

    /// The team's walkers gathered at the latest stop.
    private var team: some View {
        let members = dashboard.members
        return HStack(spacing: -4) {
            ForEach(members.prefix(5)) { member in
                VStack(spacing: 0) {
                    WalkingCharacter(avatarID: member.avatarID, outfit: model.outfit(for: member.id), walking: (member.dayMeters ?? 0) > 0, pixel: 1.6,
                                     phase: Double(member.username.count))
                        .frame(width: 26, height: 36)
                    Text(member.isCurrentUser ? "You" : member.username)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(member.isCurrentUser ? Theme.Palette.gold : Theme.Palette.cream)
                        .lineLimit(1)
                        .frame(width: 34)
                }
            }
            if members.count > 5 {
                Text("+\(members.count - 5)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.cream)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.ink.opacity(0.55)))
    }

    /// A number in 0..<1 fixed by this stop and `k`, so scenery stays put.
    private func rand(_ k: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: index &* 7_919 &+ k &* 104_729 &+ 12_345)
        x ^= x >> 33
        x &*= 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    /// A few props from the region's set, kept clear of the trail.
    private func scenery(world: TeamWorld?, pathX: CGFloat) -> some View {
        let props: [String]
        switch world?.tint {
        case .enchanted: props = ["mushroom", "map-pine", "map-flowers", "map-bush"]
        case .crystal: props = ["crystal", "map-rock", "map-pine"]
        case .desert: props = ["map-cactus", "map-rock", "map-ruin"]
        case .skyward: props = ["map-cloud", "map-flowers", "map-bush"]
        case .ancient: props = ["map-ruin", "map-rock", "map-tree"]
        case nil: props = ["map-tree", "map-pine", "map-bush", "map-flowers", "map-rock"]
        }
        return ZStack {
            ForEach(0..<4, id: \.self) { k in
                let px = width * (0.05 + rand(k * 3) * 0.9)
                if abs(px - pathX) > 52 {
                    ItemIcon(spriteID: props[Int(rand(k * 3 + 1) * Double(props.count)) % props.count],
                             pixel: 2.2 + rand(k * 3 + 2) * 1.2)
                        .position(x: px, y: 16 + rand(k * 3 + 2) * (height - 32))
                }
            }
        }
    }

    private func regionColor(_ world: TeamWorld?) -> Color {
        switch world?.tint {
        case .enchanted: return Color(hex: 0x3B3466)
        case .crystal: return Color(hex: 0x3F6A8C)
        case .desert: return Color(hex: 0x9A7442)
        case .skyward: return Color(hex: 0x5A8FC0)
        case .ancient: return Color(hex: 0x6B5E52)
        case nil: return Color(hex: 0x3E6B45)
        }
    }

    private func accessibilityText(_ landmarks: [TeamMap.Landmark]) -> String {
        let km = DistanceFormatting.kilometres(index * TeamMap.waypointMeters)
        let state = index == reached ? "Your team is here" : (index < reached ? "Reached" : "Not reached yet")
        let names = landmarks.map(\.title).joined(separator: ", ")
        return "Stop \(index), \(km). \(state)." + (names.isEmpty ? "" : " \(names).")
    }
}
