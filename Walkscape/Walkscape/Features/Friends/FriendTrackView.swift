import SwiftUI
import WalkscapeDomain

/// The shared daily track: everyone's walking distance on one horizontal path.
///
/// Layout (which metres are visible, where each sprite goes, who becomes an
/// edge indicator) comes entirely from `FriendTrackLayoutEngine`; this view
/// only draws it. Positions represent walking distance, never location.
struct FriendTrackView: View {
    enum Style { case full, compact }

    @Environment(AppModel.self) private var model
    var style: Style = .full

    @State private var previousRange: TrackRange?
    @State private var dragStartRange: TrackRange?

    private var metrics: TrackMetrics { TrackMetrics(style: style) }

    var body: some View {
        GeometryReader { geometry in
            let viewport = FriendTrackLayoutEngine.layout(TrackLayoutInput(
                participants: model.trackParticipants,
                // The compact preview always centres on the user.
                focus: style == .full ? model.trackFocus.focus : .currentUser,
                configuration: metrics.configuration(width: geometry.size.width),
                previousRange: previousRange))
            let feetY = geometry.size.height - metrics.labelHeight - metrics.bottomPadding

            ZStack(alignment: .topLeading) {
                TrackBackdrop(biome: model.engine.catalog.zone(forMeters: viewport.range.center).biome,
                              size: geometry.size, feetY: feetY)

                if style == .full {
                    TrackRuler(viewport: viewport, catalog: model.engine.catalog)
                }

                // Back lanes first so the front row draws on top.
                ForEach(viewport.characterPositions.sorted { $0.lane > $1.lane }) { position in
                    TrackCharacter(position: position, metrics: metrics, now: model.now)
                        .position(x: position.x,
                                  y: feetY - CGFloat(position.lane) * metrics.laneHeight - metrics.characterHeight / 2
                                      + metrics.labelHeight / 2)
                        .onTapGesture {
                            if style == .compact {
                                model.showOnTrack(position.id)
                            } else {
                                withAnimation(.trackFocus) { model.trackFocus.focus(on: position.id, currentUserID: model.currentUserID) }
                            }
                        }
                }

                indicatorColumn(viewport.leftOverflow, edge: .leading, size: geometry.size)
                indicatorColumn(viewport.rightOverflow, edge: .trailing, size: geometry.size)

                if style == .full && model.trackFocus.showsBackToMe {
                    BackToMeButton {
                        withAnimation(.trackFocus) { model.trackFocus.backToMe() }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 34)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .strokeBorder(Theme.Palette.ink, lineWidth: 2)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewport), including: style == .full ? .all : .subviews)
            .animation(.trackFocus, value: viewport.range)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewport.characterPositions)
            .onChange(of: viewport.range, initial: true) { _, range in previousRange = range }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Shared daily track, showing \(DistanceFormatting.kilometres(viewport.range.lower)) to \(DistanceFormatting.kilometres(viewport.range.upper))")
        }
        .frame(height: metrics.height)
    }

    /// Dragging switches to a free range that data refreshes won't move.
    private func dragGesture(_ viewport: TrackViewport) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let start = dragStartRange ?? viewport.range
                if dragStartRange == nil { dragStartRange = viewport.range }
                let delta = Int((-value.translation.width / viewport.distanceScale).rounded())
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { model.trackFocus.pan(from: start, deltaMeters: delta) }
            }
            .onEnded { _ in dragStartRange = nil }
    }

    @ViewBuilder
    private func indicatorColumn(_ indicators: [OverflowIndicator], edge: HorizontalEdge, size: CGSize) -> some View {
        if !indicators.isEmpty {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(indicators) { indicator in
                    OverflowIndicatorView(indicator: indicator, compact: style == .compact) {
                        if style == .compact {
                            model.showOnTrack(indicator.targetUserID)
                        } else {
                            withAnimation(.trackFocus) {
                                model.trackFocus.select(indicator, currentUserID: model.currentUserID)
                            }
                        }
                    }
                }
            }
            .frame(width: metrics.indicatorWidth)
            .frame(maxHeight: .infinity)
            .padding(.top, style == .full ? 20 : 0)
            .frame(width: size.width - 2 * metrics.edgeInset, alignment: edge == .leading ? .leading : .trailing)
            .padding(.horizontal, metrics.edgeInset)
            .transition(.opacity)
        }
    }
}

extension Animation {
    static let trackFocus = Animation.spring(response: 0.6, dampingFraction: 0.86)
}

/// Sizes for the two track styles.
struct TrackMetrics {
    let style: FriendTrackView.Style

    var pixel: CGFloat { style == .full ? 2.5 : 2 }
    var characterWidth: CGFloat { 16 * pixel }
    var characterHeight: CGFloat { 20 * pixel }
    var labelHeight: CGFloat { style == .full ? 30 : 26 }
    var laneHeight: CGFloat { characterHeight + labelHeight - 4 }
    var labelWidth: CGFloat { style == .full ? 66 : 58 }
    var indicatorWidth: CGFloat { style == .full ? 74 : 62 }
    var edgeInset: CGFloat { 6 }
    var bottomPadding: CGFloat { 2 }
    var laneCount: Int { style == .full ? 3 : 2 }
    var height: CGFloat {
        style == .full ? 28 + CGFloat(laneCount) * laneHeight + bottomPadding : CGFloat(laneCount) * laneHeight + 8
    }

    func configuration(width: CGFloat) -> TrackLayoutConfiguration {
        TrackLayoutConfiguration(viewportWidth: Double(width), characterWidth: Double(characterWidth),
                                 labelWidth: Double(labelWidth), edgeInset: Double(edgeInset),
                                 indicatorWidth: Double(indicatorWidth), laneCount: laneCount)
    }
}

/// The landscape behind the track: the biome at the centre of the visible
/// range, so panning to a friend 7 km ahead shows the zone they're in.
private struct TrackBackdrop: View {
    let biome: Biome
    let size: CGSize
    let feetY: CGFloat

    var body: some View {
        // Size the scene so its path lines up with the front row's feet.
        let sceneHeight = max(size.height, feetY / 0.83)
        PixelSceneView(biome: biome, walking: false, pixel: 2.5)
            .frame(width: size.width, height: sceneHeight)
            .frame(width: size.width, height: size.height, alignment: .top)
            .overlay(Theme.Palette.night.opacity(0.12))
            .id(biome)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.6), value: biome)
    }
}

/// Distance ticks along the top, with zone boundaries marked.
private struct TrackRuler: View {
    let viewport: TrackViewport
    let catalog: ZoneCatalog

    var body: some View {
        let span = viewport.range.span
        let step = span <= 600 ? 100 : (span <= 1_500 ? 250 : 500)
        let first = ((viewport.range.lower + step - 1) / step) * step
        let ticks = Array(stride(from: first, through: viewport.range.upper, by: step))
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.Palette.ink.opacity(0.55))
                .frame(height: 22)
            ForEach(ticks, id: \.self) { meters in
                let isBoundary = meters % 1_000 == 0
                VStack(spacing: 1) {
                    Text(isBoundary ? catalog.zone(forMeters: meters).name : DistanceFormatting.kilometres(meters))
                        .font(.system(size: 9, weight: isBoundary ? .heavy : .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isBoundary ? Theme.Palette.gold : Theme.Palette.creamDim)
                        .lineLimit(1)
                        .fixedSize()
                    Rectangle()
                        .fill(isBoundary ? Theme.Palette.gold : Theme.Palette.creamDim.opacity(0.6))
                        .frame(width: isBoundary ? 2 : 1, height: isBoundary ? 8 : 5)
                }
                .position(x: viewport.x(forMeters: meters), y: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One walker on the track with their name and distance.
private struct TrackCharacter: View {
    @Environment(AppModel.self) private var model
    let position: CharacterPosition
    let metrics: TrackMetrics
    let now: Date

    var body: some View {
        let participant = position.participant
        let isStale = participant.availability == .stale
        VStack(spacing: 0) {
            WalkingCharacter(avatarID: participant.avatarID, outfit: model.outfit(for: participant.id),
                             walking: !isStale && (participant.distanceMeters ?? 0) > 0,
                             pixel: metrics.pixel, phase: walkPhase(participant.id))
                .opacity(isStale ? 0.6 : 1)
                .overlay(alignment: .bottom) {
                    if position.isFocused {
                        Ellipse()
                            .stroke(Theme.Palette.gold, lineWidth: 2)
                            .frame(width: metrics.characterWidth * 0.9, height: 8)
                            .offset(y: 3)
                    }
                }
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    if isStale { Image(systemName: "clock").font(.system(size: 8, weight: .bold)) }
                    Text(participant.name).lineLimit(1)
                }
                .font(.system(size: metrics.style == .full ? 11 : 10, weight: .heavy, design: .rounded))
                .foregroundStyle(participant.isCurrentUser ? Theme.Palette.gold : Theme.Palette.cream)
                Text((participant.isDistanceEstimated ? "≈" : "") + DistanceFormatting.kilometres(participant.distanceMeters ?? 0))
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(maxWidth: metrics.labelWidth - 4)
            .background(Capsule().fill(Theme.Palette.ink.opacity(position.isFocused ? 0.9 : 0.7)))
            .overlay(Capsule().strokeBorder(position.isFocused ? Theme.Palette.gold : .clear, lineWidth: 1))
            .frame(height: metrics.labelHeight)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(participant.isCurrentUser ? "" : "Focus the track on \(participant.name)")
    }

    /// Stable per-walker offset so the crowd doesn't step in unison.
    private func walkPhase(_ id: UserID) -> Double {
        Double(id.rawValue.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 8) / 8
    }

    private var accessibilityText: String {
        let participant = position.participant
        var text = "\(participant.name), \(DistanceFormatting.kilometres(participant.distanceMeters ?? 0)) today"
        if participant.isDistanceEstimated { text += ", estimated" }
        if participant.availability == .stale, let updated = participant.updatedAt {
            text += ", last updated \(RelativeTime.short(since: updated, now: now))"
        }
        return text
    }
}

/// A tappable badge at the edge for walkers outside the visible range.
struct OverflowIndicatorView: View {
    let indicator: OverflowIndicator
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: -8) {
                    ForEach(indicator.members.prefix(3)) { member in
                        AvatarPortrait(avatarID: member.avatarID, size: compact ? 20 : 24,
                                       ring: member.isCurrentUser ? Theme.Palette.gold : Theme.Palette.ink)
                    }
                }
                Text(indicator.title)
                    .font(.system(size: compact ? 10 : 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(indicator.includesCurrentUser ? Theme.Palette.gold : Theme.Palette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 2) {
                    if indicator.direction == .behind { Image(systemName: "arrow.left") }
                    Text(indicator.detail).lineLimit(1).minimumScaleFactor(0.7)
                    if indicator.direction == .ahead { Image(systemName: "arrow.right") }
                }
                .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Palette.creamDim)
            }
            .padding(.vertical, Theme.Spacing.xs + 1)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestDeep.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(indicator.accessibilityLabel)
    }
}

struct BackToMeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back to me", systemImage: "scope")
        }
        .buttonStyle(.pixel)
        .accessibilityHint("Returns the track to your position")
    }
}
