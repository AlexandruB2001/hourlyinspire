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
        static func journal(_ source: WalkingDataSourceKind) -> String { "walkscape.journal.v1.\(source.rawValue)" }
        static func companion(_ source: WalkingDataSourceKind) -> String { "walkscape.companion.v1.\(source.rawValue)" }
        static let companionSpecies = "walkscape.companionSpecies.v1"
        static let pendingReferralCode = "walkscape.pendingReferralCode.v1"
        static let ads = "walkscape.ads.v1"
        static func ledger(_ source: WalkingDataSourceKind) -> String { "walkscape.ledger.v1.\(source.rawValue)" }
        static let cloudSaveOwner = "walkscape.cloudSaveOwner.v1"
        static let showcase = "walkscape.showcase.v1"
        static let premiumLook = "walkscape.premiumLook.v1"
        static func collections(_ source: WalkingDataSourceKind) -> String { "walkscape.collections.v1.\(source.rawValue)" }
        static func quests(_ source: WalkingDataSourceKind) -> String { "walkscape.quests.v1.\(source.rawValue)" }
        static let notificationPreferences = "walkscape.notificationPreferences.v1"
        static let notificationLedger = "walkscape.notificationLedger.v1"
        static let seenTips = "walkscape.seenTips.v1"
        static func companionRoster(_ source: WalkingDataSourceKind) -> String { "walkscape.companionRoster.v1.\(source.rawValue)" }
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

    func loadJournal(_ source: WalkingDataSourceKind) -> JourneyJournal {
        load(JourneyJournal.self, Key.journal(source)) ?? JourneyJournal()
    }

    func save(_ journal: JourneyJournal, for source: WalkingDataSourceKind) {
        save(journal, Key.journal(source))
    }

    // The chosen species is shared; growth is per data source so demo walking
    // never grows the real companion.
    var companionSpeciesID: String? {
        get { defaults.string(forKey: Key.companionSpecies) }
        nonmutating set { defaults.set(newValue, forKey: Key.companionSpecies) }
    }

    func loadCompanionRoster(_ source: WalkingDataSourceKind) -> CompanionRoster {
        load(CompanionRoster.self, Key.companionRoster(source)) ?? CompanionRoster()
    }

    func save(_ roster: CompanionRoster, for source: WalkingDataSourceKind) {
        save(roster, Key.companionRoster(source))
    }

    func loadCompanion(_ source: WalkingDataSourceKind) -> CompanionState? {
        load(CompanionState.self, Key.companion(source))
    }

    func save(_ companion: CompanionState?, for source: WalkingDataSourceKind) {
        if let companion { save(companion, Key.companion(source)) } else { defaults.removeObject(forKey: Key.companion(source)) }
    }

    /// A referral code entered before signing in, redeemed once an account exists.
    var pendingReferralCode: String? {
        get { defaults.string(forKey: Key.pendingReferralCode) }
        nonmutating set { defaults.set(newValue, forKey: Key.pendingReferralCode) }
    }

    // Rewards are per data source, like coins.
    func loadLedger(_ source: WalkingDataSourceKind) -> RewardLedger {
        load(RewardLedger.self, Key.ledger(source)) ?? RewardLedger()
    }

    func save(_ ledger: RewardLedger, for source: WalkingDataSourceKind) {
        save(ledger, Key.ledger(source))
    }

    func loadQuestTracker(_ source: WalkingDataSourceKind) -> QuestTracker {
        load(QuestTracker.self, Key.quests(source)) ?? QuestTracker()
    }

    func save(_ tracker: QuestTracker, for source: WalkingDataSourceKind) {
        save(tracker, Key.quests(source))
    }

    func loadCollections(_ source: WalkingDataSourceKind) -> CollectionState {
        load(CollectionState.self, Key.collections(source)) ?? CollectionState()
    }

    func save(_ collections: CollectionState, for source: WalkingDataSourceKind) {
        save(collections, Key.collections(source))
    }

    func loadPremiumLook() -> PremiumLook { load(PremiumLook.self, Key.premiumLook) ?? PremiumLook() }
    func save(_ look: PremiumLook) { save(look, Key.premiumLook) }

    func loadShowcase() -> ProfileShowcase { load(ProfileShowcase.self, Key.showcase) ?? ProfileShowcase() }
    func save(_ showcase: ProfileShowcase) { save(showcase, Key.showcase) }

    /// The account this phone's Apple Health progress was last saved to.
    /// First-time tips already shown and dismissed.
    var seenTips: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.seenTips) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Key.seenTips) }
    }

    var cloudSaveOwner: String? {
        get { defaults.string(forKey: Key.cloudSaveOwner) }
        nonmutating set { defaults.set(newValue, forKey: Key.cloudSaveOwner) }
    }

    // Ad limits are per device, not per data source.
    func loadAdState() -> AdState {
        if let saved = load(AdState.self, Key.ads) { return saved }
        let fresh = AdState(firstLaunch: Date())
        save(fresh)
        return fresh
    }

    func save(_ ads: AdState) { save(ads, Key.ads) }

    /// The old "Daily walk reminder" setting carries over the first time.
    func loadNotificationPreferences(legacyReminder: Bool) -> NotificationPreferences {
        load(NotificationPreferences.self, Key.notificationPreferences) ?? NotificationPreferences(dailyReminder: legacyReminder)
    }

    func save(_ preferences: NotificationPreferences) { save(preferences, Key.notificationPreferences) }

    func loadNotificationLedger() -> NotificationLedger {
        load(NotificationLedger.self, Key.notificationLedger) ?? NotificationLedger()
    }

    func save(_ ledger: NotificationLedger) { save(ledger, Key.notificationLedger) }

    /// The last successful daily totals, shown (with their age) while offline.
    func loadLastProgress(_ source: WalkingDataSourceKind) -> DailyProgress? {
        load(DailyProgress.self, Key.lastProgress(source))
    }

    func save(lastProgress: DailyProgress, for source: WalkingDataSourceKind) {
        save(lastProgress, Key.lastProgress(source))
    }

    func reset() {
        var keys = [Key.settings, Key.companionSpecies, Key.pendingReferralCode, Key.cloudSaveOwner, Key.showcase, Key.premiumLook]
        for source in WalkingDataSourceKind.allCases {
            keys += [Key.progression(source), Key.lastProgress(source), Key.wallet(source), Key.journal(source), Key.companion(source),
                     Key.ledger(source), Key.quests(source), Key.collections(source)]
        }
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
