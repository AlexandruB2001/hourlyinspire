import Foundation

/// Computes the distance-aware viewport for the shared daily track.
///
/// The engine is deterministic: the same input always produces the same
/// viewport. It only decides *presentation* (which metres are on screen and
/// where each sprite is drawn); distances are never altered.
///
/// Range selection:
/// - `.currentUser`: find the largest group of participants that includes the
///   current user and fits inside `maximumSpanMeters`, then fit the range to
///   that group (at least `minimumSpanMeters`, rounded to `spanStepMeters`).
/// - `.participant`: centre on that participant and widen symmetrically to
///   include neighbours within half the maximum span.
/// - `.free`: use the range the user dragged to.
///
/// Everyone outside the range becomes an edge indicator. Friends past the same
/// edge are grouped when there is more than one; the current user always gets
/// their own indicator so "where am I?" is never hidden in a group.
public enum FriendTrackLayoutEngine {
    public static func layout(_ input: TrackLayoutInput) -> TrackViewport {
        let config = input.configuration

        var seen = Set<UserID>()
        let participants = input.participants.filter { seen.insert($0.id).inserted }
        let currentUser = participants.first(where: \.isCurrentUser)
        let placeable = participants.filter(\.isPlaceable).sorted(by: distanceOrder)
        let unavailable = participants.filter { !$0.isPlaceable }

        let focus = resolveFocus(input.focus, currentUser: currentUser, placeable: placeable, config: config)
        let focusedUserID: UserID? = {
            switch focus {
            case .currentUser: return currentUser?.id
            case .participant(let id): return id
            case .free: return nil
            }
        }()

        let range = selectRange(focus: focus, currentUser: currentUser, placeable: placeable,
                                previous: input.previousRange, config: config)

        let behind = placeable.filter { $0.distanceMeters! < range.lower }.reversed()
        let ahead = placeable.filter { $0.distanceMeters! > range.upper }
        let visible = placeable.filter { range.contains($0.distanceMeters!) }

        let leftReserve = behind.isEmpty ? 0 : config.indicatorWidth
        let rightReserve = ahead.isEmpty ? 0 : config.indicatorWidth
        let plotMinX = config.edgeInset + config.characterWidth / 2 + leftReserve
        let plotMaxX = max(plotMinX + 1, config.viewportWidth - config.edgeInset - config.characterWidth / 2 - rightReserve)
        let scale = (plotMaxX - plotMinX) / Double(range.span)

        let positions = assignLanes(visible: visible, focusedUserID: focusedUserID, range: range,
                                    plotMinX: plotMinX, scale: scale, config: config)

        let currentUserMeters = currentUser?.distanceMeters ?? 0
        return TrackViewport(
            focus: focus,
            focusedUserID: focusedUserID,
            range: range,
            distanceScale: scale,
            plotMinX: plotMinX,
            plotMaxX: plotMaxX,
            characterPositions: positions,
            leftOverflow: indicators(for: Array(behind), direction: .behind, currentUserMeters: currentUserMeters),
            rightOverflow: indicators(for: ahead, direction: .ahead, currentUserMeters: currentUserMeters),
            unavailableParticipants: unavailable,
            isCurrentUserVisible: positions.contains { $0.participant.isCurrentUser }
        )
    }

    // MARK: - Focus

    private static func resolveFocus(_ focus: TrackFocus, currentUser: TrackParticipant?,
                                     placeable: [TrackParticipant], config: TrackLayoutConfiguration) -> TrackFocus {
        switch focus {
        case .currentUser:
            return .currentUser
        case .participant(let id):
            if id == currentUser?.id { return .currentUser }
            // Focus on someone who left or has no data falls back to the user.
            return placeable.contains { $0.id == id } ? focus : .currentUser
        case .free(let center, let span):
            let span = min(max(span, config.minimumSpanMeters), config.maximumSpanMeters)
            return .free(centerMeters: max(0, center), spanMeters: span)
        }
    }

    // MARK: - Range

    private static func selectRange(focus: TrackFocus, currentUser: TrackParticipant?, placeable: [TrackParticipant],
                                    previous: TrackRange?, config: TrackLayoutConfiguration) -> TrackRange {
        switch focus {
        case .free(let center, let span):
            return clampedRange(lower: center - span / 2, span: span)

        case .participant(let id):
            let target = placeable.first { $0.id == id }!.distanceMeters!
            let halfMax = config.maximumSpanMeters / 2
            let reach = placeable.map { abs($0.distanceMeters! - target) }.filter { $0 <= halfMax }.max() ?? 0
            let span = fittedSpan(spread: reach * 2, config: config)
            let fresh = clampedRange(lower: target - span / 2, span: span)
            let required = placeable.map(\.distanceMeters!).filter { abs($0 - target) <= halfMax }
            if let previous, canKeep(previous, fresh: fresh, required: required, config: config),
               abs(target - previous.center) <= previous.span / 4 {
                return previous
            }
            return fresh

        case .currentUser:
            guard !placeable.isEmpty else {
                return TrackRange(lower: 0, upper: fittedSpan(spread: 0, config: config))
            }
            let focusIndex = placeable.firstIndex { $0.isCurrentUser } ?? 0
            let distances = placeable.map(\.distanceMeters!)
            let (first, last) = bestCluster(distances, containing: focusIndex, maxSpread: config.maximumSpanMeters)
            let clusterMin = distances[first]
            let clusterMax = distances[last]
            let span = fittedSpan(spread: clusterMax - clusterMin, config: config)

            let midpoint = (clusterMin + clusterMax) / 2
            let step = config.centerStepMeters
            let center = ((midpoint + step / 2) / step) * step
            var lower = center - span / 2
            if clusterMin < lower { lower = clusterMin }
            if clusterMax > lower + span { lower = clusterMax - span }
            let fresh = clampedRange(lower: lower, span: span)

            if let previous, canKeep(previous, fresh: fresh, required: Array(distances[first...last]), config: config) {
                return previous
            }
            return fresh
        }
    }

    /// The largest run of sorted distances containing `index` whose spread fits.
    /// Ties prefer the tighter run, then the run centred closest to the focus,
    /// then the lower run, so the result is deterministic.
    static func bestCluster(_ sorted: [Int], containing index: Int, maxSpread: Int) -> (Int, Int) {
        let focus = sorted[index]
        var best = (index, index)
        var bestScore = (count: 1, spread: 0, offset: 0)
        var start = index
        while start >= 0, focus - sorted[start] <= maxSpread {
            var end = index
            while end + 1 < sorted.count, sorted[end + 1] - sorted[start] <= maxSpread { end += 1 }
            let count = end - start + 1
            let spread = sorted[end] - sorted[start]
            let offset = abs((sorted[start] + sorted[end]) / 2 - focus)
            let better = count > bestScore.count
                || (count == bestScore.count && spread < bestScore.spread)
                || (count == bestScore.count && spread == bestScore.spread && offset < bestScore.offset)
                || (count == bestScore.count && spread == bestScore.spread && offset == bestScore.offset && start < best.0)
            if better {
                best = (start, end)
                bestScore = (count, spread, offset)
            }
            start -= 1
        }
        return best
    }

    private static func fittedSpan(spread: Int, config: TrackLayoutConfiguration) -> Int {
        let step = config.spanStepMeters
        let rounded = ((max(spread, config.minimumSpanMeters) + step - 1) / step) * step
        return max(spread, min(rounded, config.maximumSpanMeters))
    }

    private static func clampedRange(lower: Int, span: Int) -> TrackRange {
        let lower = max(0, lower)
        return TrackRange(lower: lower, upper: lower + span)
    }

    /// Hysteresis: keep the on-screen range while it still shows everyone it
    /// needs to and its scale is close to the freshly computed one.
    private static func canKeep(_ previous: TrackRange, fresh: TrackRange, required: [Int],
                                config: TrackLayoutConfiguration) -> Bool {
        guard previous.lower >= 0,
              previous.span >= config.minimumSpanMeters,
              previous.span <= config.maximumSpanMeters,
              abs(previous.span - fresh.span) <= 2 * config.spanStepMeters else { return false }
        return required.allSatisfy(previous.contains)
    }

    // MARK: - Lanes

    private static func assignLanes(visible: [TrackParticipant], focusedUserID: UserID?, range: TrackRange,
                                    plotMinX: Double, scale: Double,
                                    config: TrackLayoutConfiguration) -> [CharacterPosition] {
        func exactX(_ participant: TrackParticipant) -> Double {
            plotMinX + Double(participant.distanceMeters! - range.lower) * scale
        }
        func priority(_ participant: TrackParticipant) -> Int {
            if participant.isCurrentUser { return 0 }
            if participant.id == focusedUserID { return 1 }
            return 2
        }
        // The user and the focused friend claim the front row first.
        let ordered = visible.sorted {
            let (a, b) = (priority($0), priority($1))
            if a != b { return a < b }
            let (ax, bx) = (exactX($0), exactX($1))
            if ax != bx { return ax < bx }
            return nameOrder($0, $1)
        }

        let width = config.labelWidth
        var lanes = Array(repeating: [Double](), count: config.laneCount)
        var positions: [CharacterPosition] = []
        for participant in ordered {
            let target = exactX(participant)
            var bestLane = 0
            var bestX = target
            var bestDisplacement = Double.infinity
            for lane in 0..<lanes.count {
                let x = nearestFreeX(target, occupied: lanes[lane], width: width)
                let displacement = abs(x - target)
                if displacement < bestDisplacement - 0.001 {
                    bestLane = lane
                    bestX = x
                    bestDisplacement = displacement
                }
            }
            lanes[bestLane].append(bestX)
            positions.append(CharacterPosition(participant: participant, x: bestX, exactX: target, lane: bestLane,
                                               isFocused: participant.id == focusedUserID))
        }
        return positions.sorted {
            if $0.exactX != $1.exactX { return $0.exactX < $1.exactX }
            return nameOrder($0.participant, $1.participant)
        }
    }

    /// The x closest to `target` that is at least `width` from every occupied x.
    static func nearestFreeX(_ target: Double, occupied: [Double], width: Double) -> Double {
        func isFree(_ x: Double) -> Bool { occupied.allSatisfy { abs($0 - x) >= width - 0.001 } }
        if isFree(target) { return target }
        let candidates = occupied.flatMap { [$0 + width, $0 - width] }.filter(isFree)
        return candidates.min {
            let (a, b) = (abs($0 - target), abs($1 - target))
            return a != b ? a < b : $0 > $1
        } ?? (occupied.max() ?? target) + width
    }

    // MARK: - Indicators

    private static func indicators(for members: [TrackParticipant], direction: OverflowDirection,
                                   currentUserMeters: Int) -> [OverflowIndicator] {
        var result: [OverflowIndicator] = []
        if let me = members.first(where: \.isCurrentUser) {
            let meters = me.distanceMeters ?? 0
            let side = direction == .ahead ? "right" : "left"
            result.append(OverflowIndicator(
                direction: direction, members: [me], targetUserID: me.id, gapFromCurrentUserMeters: 0,
                title: "You", detail: DistanceFormatting.kilometres(meters),
                accessibilityLabel: "You, \(DistanceFormatting.kilometres(meters)) today, off screen to the \(side). Double tap to return to you."))
        }
        let friends = members.filter { !$0.isCurrentUser }
        guard let nearest = friends.first else { return result }
        let gap = nearest.distanceMeters! - currentUserMeters
        let side = direction == .ahead ? "right" : "left"
        if friends.count == 1 {
            result.append(OverflowIndicator(
                direction: direction, members: friends, targetUserID: nearest.id, gapFromCurrentUserMeters: gap,
                title: nearest.name, detail: GapText.short(gap),
                accessibilityLabel: "\(nearest.name), \(GapText.spoken(gap)), off screen to the \(side). Double tap to focus."))
        } else {
            let gaps = friends.map { $0.distanceMeters! - currentUserMeters }
            // "ahead"/"behind" are relative to the user, so only use them when true for everyone.
            let title: String
            let detail: String
            if gaps.allSatisfy({ $0 > 0 }) {
                (title, detail) = ("\(friends.count) friends", "ahead")
            } else if gaps.allSatisfy({ $0 < 0 }) {
                (title, detail) = ("\(friends.count) friends", "behind")
            } else {
                (title, detail) = ("\(friends.count) more", "friends")
            }
            let names = friends.map(\.name).joined(separator: ", ")
            result.append(OverflowIndicator(
                direction: direction, members: friends, targetUserID: nearest.id, gapFromCurrentUserMeters: gap,
                title: title, detail: detail,
                accessibilityLabel: "\(friends.count) friends off screen to the \(side): \(names). Nearest is \(nearest.name), \(GapText.spoken(gap)). Double tap to focus on \(nearest.name)."))
        }
        return result
    }

    // MARK: - Ordering

    private static func distanceOrder(_ a: TrackParticipant, _ b: TrackParticipant) -> Bool {
        let (da, db) = (a.distanceMeters ?? 0, b.distanceMeters ?? 0)
        if da != db { return da < db }
        if a.isCurrentUser != b.isCurrentUser { return a.isCurrentUser }
        return nameOrder(a, b)
    }

    private static func nameOrder(_ a: TrackParticipant, _ b: TrackParticipant) -> Bool {
        a.name != b.name ? a.name < b.name : a.id < b.id
    }
}

/// Text describing a walking-distance gap. Never implies physical proximity.
public enum GapText {
    /// "+4.8 km", "2.1 km behind", "level".
    public static func short(_ gap: Int) -> String {
        if (abs(gap) + 50) / 100 == 0 { return "level" }
        return gap > 0 ? "+\(DistanceFormatting.gap(gap))" : "\(DistanceFormatting.gap(gap)) behind"
    }

    /// "4.8 km ahead of you".
    public static func spoken(_ gap: Int) -> String {
        if (abs(gap) + 50) / 100 == 0 { return "level with you" }
        return gap > 0 ? "\(DistanceFormatting.gap(gap)) ahead of you" : "\(DistanceFormatting.gap(gap)) behind you"
    }

    /// "Taylor has walked 4.8 km farther than you today."
    public static func comparison(name: String, gap: Int) -> String {
        if (abs(gap) + 50) / 100 == 0 { return "You and \(name) have walked about the same distance today." }
        return gap > 0
            ? "\(name) has walked \(DistanceFormatting.gap(gap)) farther than you today."
            : "\(name) has walked \(DistanceFormatting.gap(gap)) less than you today."
    }
}
