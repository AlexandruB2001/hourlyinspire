import Foundation

/// The newest TestFlight build, as published in `latest.json` on the
/// developer site. Testers on an older build are asked to update.
public struct BetaUpdate: Codable, Hashable, Sendable, Identifiable {
    public let build: Int
    /// One line on what's new.
    public let notes: String

    public var id: Int { build }

    public init(build: Int, notes: String) {
        self.build = build
        self.notes = notes
    }

    public static let url = URL(string: "https://alexandrub2001.github.io/latest.json")!
    /// The Friends group's public link: it opens the TestFlight app on Walkscape.
    public static let testFlightURL = URL(string: "https://testflight.apple.com/join/A2HmzFYV")!
    /// "Later" waits this long before asking about the same build again.
    public static let snooze: TimeInterval = 24 * 60 * 60

    /// Whether to show the pop-up: a newer build, and not snoozed for it.
    public func shouldPrompt(currentBuild: Int, snoozedBuild: Int?, snoozedUntil: Date?, now: Date) -> Bool {
        guard build > currentBuild else { return false }
        if let snoozedBuild, snoozedBuild >= build, let snoozedUntil, now < snoozedUntil { return false }
        return true
    }
}
