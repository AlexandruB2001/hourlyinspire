import Foundation

/// A snapshot of where a distance sits on the journey.
public struct ZoneProgress: Hashable, Sendable {
    public let distanceMeters: Int
    public let zoneIndex: Int
    public let currentZone: Zone
    public let nextZone: Zone
    public let metersIntoZone: Int
    public let metersToNextZone: Int

    /// 0...1 progress through the current zone.
    public var fractionThroughZone: Double {
        guard currentZone.lengthMeters > 0 else { return 0 }
        return min(1, max(0, Double(metersIntoZone) / Double(currentZone.lengthMeters)))
    }

    /// Number of zone boundaries crossed (the starting zone is index 0).
    public var boundariesCrossed: Int { zoneIndex }
}

/// Pure mapping from distance to zones. Holds no state.
public struct ZoneProgressionEngine: Sendable {
    public let catalog: ZoneCatalog

    public init(catalog: ZoneCatalog = .standard) {
        self.catalog = catalog
    }

    public func progress(forMeters meters: Int) -> ZoneProgress {
        let meters = max(0, meters)
        let index = catalog.zoneIndex(forMeters: meters)
        let zone = catalog.zone(at: index)
        return ZoneProgress(distanceMeters: meters,
                            zoneIndex: index,
                            currentZone: zone,
                            nextZone: catalog.zone(at: index + 1),
                            metersIntoZone: meters - zone.startMeters,
                            metersToNextZone: zone.endMeters - meters)
    }
}
