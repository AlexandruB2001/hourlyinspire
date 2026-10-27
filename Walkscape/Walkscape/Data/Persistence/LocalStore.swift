import Foundation
import WalkscapeDomain

/// User preferences that live on the device.
struct AppSettings: Codable, Equatable {
    var username = "Wanderer"
    var avatarID = AvatarCatalog.defaultID
    /// `nil` until the user picks a source; then the app chooses a sensible default.
    var dataSource: WalkingDataSourceKind?
    var shareProgressWithFriends = true
    var dailyReminderEnabled = false
}

/// Small JSON-in-UserDefaults persistence. Lifetime progression is tiny
/// (one integer per day), so a database isn't needed yet.
struct LocalStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let settings = "walkscape.settings.v1"
        static func progression(_ source: WalkingDataSourceKind) -> String { "walkscape.progression.v1.\(source.rawValue)" }
        static func lastProgress(_ source: WalkingDataSourceKind) -> String { "walkscape.lastProgress.v1.\(source.rawValue)" }
        static func wallet(_ source: WalkingDataSourceKind) -> String { "walkscape.wallet.v1.\(source.rawValue)" }
    }

    func loadSettings() -> AppSettings { load(AppSettings.self, Key.settings) ?? AppSettings() }
    func save(_ settings: AppSettings) { save(settings, Key.settings) }

    // Progression is stored per data source so demo walking never counts
    // toward a real lifetime total.
    func loadProgression(_ source: WalkingDataSourceKind) -> ProgressionState {
        load(ProgressionState.self, Key.progression(source)) ?? ProgressionState()
    }

    func save(_ progression: ProgressionState, for source: WalkingDataSourceKind) {
        save(progression, Key.progression(source))
    }

    // Coins are per data source too, so demo walking can't buy real outfits.
    func loadWallet(_ source: WalkingDataSourceKind) -> WalletState {
        load(WalletState.self, Key.wallet(source)) ?? WalletState()
    }

    func save(_ wallet: WalletState, for source: WalkingDataSourceKind) {
        save(wallet, Key.wallet(source))
    }

    /// The last successful daily totals, shown (with their age) while offline.
    func loadLastProgress(_ source: WalkingDataSourceKind) -> DailyProgress? {
        load(DailyProgress.self, Key.lastProgress(source))
    }

    func save(lastProgress: DailyProgress, for source: WalkingDataSourceKind) {
        save(lastProgress, Key.lastProgress(source))
    }

    func reset() {
        var keys = [Key.settings]
        for source in WalkingDataSourceKind.allCases { keys += [Key.progression(source), Key.lastProgress(source), Key.wallet(source)] }
        keys.forEach(defaults.removeObject(forKey:))
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }
}
