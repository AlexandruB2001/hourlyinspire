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
            regionColor(world).opacity(index % 2 == 0 ? 1 : 0.92)
            // The trail: half a segment up to the stop above, half down to the one below.
            Canvas { context, _ in
                var path = Path()
                if index < TeamMap.waypointCount { path.move(to: CGPoint(x: (here + x(index + 1)) / 2, y: 0)) } else {
                    path.move(to: CGPoint(x: here, y: height / 2))
                }
                path.addLine(to: CGPoint(x: here, y: height / 2))
                if index > 0 { path.addLine(to: CGPoint(x: (here + x(index - 1)) / 2, y: height)) }
                let done = index <= reached
                context.stroke(path, with: .color(done ? Theme.Palette.gold : Theme.Palette.cream.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: done ? [] : [6, 8]))
            }
            stop(isLandmark: !landmarks.isEmpty, landmark: landmarks.first)
                .position(x: here, y: height / 2)
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
        let size: CGFloat = isLandmark ? 40 : (index == reached ? 30 : 22)
        return ZStack {
            Circle().fill(done ? Theme.Palette.gold : Theme.Palette.forestRaised)
            Circle().strokeBorder(Theme.Palette.ink, lineWidth: 3)
            if let landmark {
                ItemIcon(spriteID: landmark.spriteID, pixel: 2.2)
                    .opacity(done ? 1 : 0.5)
            } else if index == reached {
                ItemIcon(spriteID: "flag", pixel: 1.8)
            } else if !done {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Theme.Palette.creamDim)
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

    private func regionColor(_ world: TeamWorld?) -> Color {
        switch world?.tint {
        case .enchanted: return Color(hex: 0x2E2A52)
        case .crystal: return Color(hex: 0x3D5A7A)
        case .desert: return Color(hex: 0x7A5A34)
        case .skyward: return Color(hex: 0x4A78A8)
        case .ancient: return Color(hex: 0x5A5048)
        case nil: return Color(hex: 0x2F4A36)
        }
    }

    private func accessibilityText(_ landmarks: [TeamMap.Landmark]) -> String {
        let km = DistanceFormatting.kilometres(index * TeamMap.waypointMeters)
        let state = index == reached ? "Your team is here" : (index < reached ? "Reached" : "Not reached yet")
        let names = landmarks.map(\.title).joined(separator: ", ")
        return "Stop \(index), \(km). \(state)." + (names.isEmpty ? "" : " \(names).")
    }
}
