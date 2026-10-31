import Foundation

/// A companion resting at camp. It keeps everything it grew while walking
/// with you, and picks up from there when it walks with you again.
public struct RestingCompanion: Codable, Hashable, Sendable {
    public var state: CompanionState
    /// Metres it had walked with you when it went to rest.
    public var walkedMeters: Int

    public init(state: CompanionState, walkedMeters: Int) {
        self.state = state
        self.walkedMeters = max(0, walkedMeters)
    }

    public var growth: CompanionGrowth { CompanionGrowth(kilometres: walkedMeters / 1_000) }
}

/// Every companion you own besides the one walking with you. A companion
/// only grows while it's the active one.
public struct CompanionRoster: Codable, Hashable, Sendable {
    /// Coins to adopt another species.
    public static let adoptionCost = 400

    public private(set) var resting: [RestingCompanion]

    public init(resting: [RestingCompanion] = []) {
        self.resting = resting
    }

    public func isResting(_ speciesID: String) -> Bool { resting.contains { $0.state.speciesID == speciesID } }

    /// Species you could still adopt.
    public func adoptable(active: CompanionState?) -> [CompanionSpecies] {
        CompanionCatalog.starters.filter { species in species.id != active?.speciesID && !isResting(species.id) }
    }

    /// The wallet key adopting `speciesID` is paid under (each species once).
    public static func adoptionChargeKey(_ speciesID: String) -> String { "companion-\(speciesID)" }

    /// Puts `active` to rest and wakes `speciesID`. Returns the new active
    /// companion, or nil if that species isn't resting here.
    public mutating func swap(active: CompanionState, to speciesID: String, lifetimeMeters: Int, at date: Date) -> CompanionState? {
        guard let index = resting.firstIndex(where: { $0.state.speciesID == speciesID }) else { return nil }
        let waking = resting.remove(at: index)
        rest(active, lifetimeMeters: lifetimeMeters)
        return waking.state.walkingAgain(walkedMeters: waking.walkedMeters, lifetimeMeters: lifetimeMeters, at: date)
    }

    /// Puts `active` to rest and returns a newly adopted `speciesID`.
    public mutating func adopt(_ speciesID: String, replacing active: CompanionState, lifetimeMeters: Int, on day: LocalDay,
                               at date: Date) -> CompanionState {
        rest(active, lifetimeMeters: lifetimeMeters)
        return CompanionState(speciesID: speciesID, adoptedOn: day, lifetimeMeters: lifetimeMeters, activeSince: date)
    }

    private mutating func rest(_ companion: CompanionState, lifetimeMeters: Int) {
        resting.removeAll { $0.state.speciesID == companion.speciesID }
        resting.append(RestingCompanion(state: companion, walkedMeters: companion.walkedMeters(lifetimeMeters: lifetimeMeters)))
    }

    /// Two devices' companions together. The one chosen most recently walks;
    /// every species owned on either side is kept, with the most it has grown.
    public static func merge(_ mine: (active: CompanionState?, roster: CompanionRoster),
                             _ theirs: (active: CompanionState?, roster: CompanionRoster),
                             lifetimeMeters: Int) -> (active: CompanionState?, roster: CompanionRoster) {
        // Every companion either side knows, as (state, metres walked).
        var known: [String: RestingCompanion] = [:]
        func add(_ state: CompanionState, walked: Int) {
            if let existing = known[state.speciesID] {
                known[state.speciesID] = RestingCompanion(state: existing.state.merged(with: state),
                                                          walkedMeters: max(existing.walkedMeters, walked))
            } else {
                known[state.speciesID] = RestingCompanion(state: state, walkedMeters: walked)
            }
        }
        // The most recently chosen walks; between companions never swapped
        // (older saves, or a new phone's first pick) the one adopted first.
        let actives = [mine.active, theirs.active].compactMap { $0 }
        let chosen = actives.sorted { a, b in
            let (since, other) = (a.activeSince ?? .distantPast, b.activeSince ?? .distantPast)
            return since != other ? since > other : a.adoptedOn < b.adoptedOn
        }.first
        for side in [mine, theirs] {
            // A companion that was only ever a first pick (never swapped or
            // adopted for coins) isn't owned unless it's the one chosen.
            if let active = side.active, active.speciesID == chosen?.speciesID || active.activeSince != nil {
                add(active, walked: active.walkedMeters(lifetimeMeters: lifetimeMeters))
            }
            for entry in side.roster.resting { add(entry.state, walked: entry.walkedMeters) }
        }
        guard let chosen else {
            return (nil, CompanionRoster(resting: known.values.sorted { $0.state.speciesID < $1.state.speciesID }))
        }
        let entry = known.removeValue(forKey: chosen.speciesID)!
        let active = entry.state.walkingAgain(walkedMeters: entry.walkedMeters, lifetimeMeters: lifetimeMeters,
                                              at: chosen.activeSince)
        return (active, CompanionRoster(resting: known.values.sorted { $0.state.speciesID < $1.state.speciesID }))
    }
}
