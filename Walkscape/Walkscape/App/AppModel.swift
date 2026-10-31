import Foundation
import Observation
import UIKit
import WalkscapeBackend
import WalkscapeDomain
import WidgetKit

/// App-wide state. Views read from it; all data flows in through `refresh*`.
/// Game logic lives in WalkscapeDomain — this type only coordinates.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case journey, friends, world, shop, profile }

    /// Where friends come from.
    enum AccountState: Equatable {
        /// No Supabase configured in this build: local sample friends.
        case localOnly
        case signedOut
        case signedIn(RemoteProfile)
    }

    // MARK: Dependencies

    let engine = ZoneProgressionEngine()
    let demoProvider = MockWalkingDataProvider()
    private let healthProvider = HealthKitWalkingDataProvider()
    /// Nil when the build has no Supabase configuration.
    let backend: WalkscapeBackend?
    private let sampleFriends: FriendRepository
    private let store: LocalStore
    let ads = AdService()
    let notifications = NotificationService.shared
    /// Real-money cosmetic purchases (StoreKit).
    let shop = StoreService()
    @ObservationIgnored private var notificationLedger: NotificationLedger
    @ObservationIgnored private var adsStarted = false
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    @ObservationIgnored private var lastAutoRefresh = Date.distantPast

    // MARK: State

    var selectedTab: Tab = .journey
    var settings: AppSettings {
        didSet { store.save(settings) }
    }
    private(set) var sync = WalkingSyncStatus()
    private(set) var progression: ProgressionState
    /// Coins, owned shop items and the current outfit.
    private(set) var wallet: WalletState
    /// Permanent log of milestones.
    private(set) var journal: JourneyJournal
    /// Every quest/event/level reward already granted, by id.
    private(set) var ledger: RewardLedger
    /// Today's and this week's quests, and the counters they need.
    private(set) var questTracker: QuestTracker
    /// Title, frame, favourite zone and showcased achievements.
    var showcase: ProfileShowcase {
        didSet {
            guard showcase != oldValue else { return }
            store.save(showcase)
            Task { await publishShowcase() }
        }
    }
    /// Friends' and teammates' titles and frames.
    private(set) var friendShowcases: [UserID: PublicShowcase] = [:]
    /// Wildlife and treasures found (postcards and memories are derived).
    private(set) var collections: CollectionState
    /// A new creature or treasure to announce; cleared by the UI.
    var discovery: DiscoveryNews?
    /// First-time tips the player has dismissed.
    private(set) var seenTips: Set<String> = []
    /// Friends' recent milestones, newest first.
    private(set) var milestoneFeed: [FriendMilestone] = []
    /// The team's shared campsite, when in a team.
    private(set) var campsite: Campsite?
    /// Everyone who has walked for the team, most first.
    private(set) var teamContributions: [TeamContribution] = []
    /// Everyone's combined distance per running seasonal event (run id → metres).
    private(set) var communityMeters: [String: Int] = [:]
    /// Purchases the server has verified for this account (any device).
    private(set) var serverEntitlements = Entitlements()
    /// Chosen companion skin, trail effect and Journal theme.
    var premiumLook: PremiumLook {
        didSet { if premiumLook != oldValue { store.save(premiumLook) } }
    }
    /// Set when the Explorer Level goes up; cleared by the UI.
    var levelUp: Int?
    @ObservationIgnored private var lastCloudSync = Date.distantPast
    @ObservationIgnored private var isSyncingCloud = false
    /// Which notifications the player wants.
    var notificationPreferences: NotificationPreferences {
        didSet {
            store.save(notificationPreferences)
            scheduleDailyReminder()
            if oldValue.social != notificationPreferences.social { Task { await registerPushToken() } }
        }
    }
    /// Ad frequency limits for this device.
    private(set) var adState: AdState
    private(set) var isWatchingAd = false
    /// Nil until the player picks a companion.
    private(set) var companion: CompanionState?
    /// Companions resting at camp (you can own one of each species).
    private(set) var companionRoster = CompanionRoster()
    /// Nil when not in a team (or not loaded yet; see `hasLoadedTeam`).
    private(set) var team: TeamDashboard?
    private(set) var teamInvites: [TeamInvite] = []
    private(set) var teamError: String?
    private(set) var isLoadingTeam = false
    private(set) var hasLoadedTeam = false
    private(set) var referral: ReferralStatus?
    private(set) var referralError: String?
    private(set) var authorization: WalkingAuthorizationState = .notDetermined
    private(set) var friends: [FriendSummary] = []
    private(set) var friendRequests = FriendRequests()
    private(set) var friendsError: String?
    private(set) var isLoadingFriends = false
    /// Set when a refresh crosses one or more zone boundaries; cleared by the UI.
    var celebration: ZoneCelebration?
    /// Milestone coins earned in the update that produced `celebration`.
    private(set) var celebrationCoins = 0
    /// The shared track's focus. Lives here so other screens can deep-link to a friend.
    var trackFocus = TrackFocusController()
    /// Ticks every 30 s so relative times and staleness stay current.
    private(set) var now = Date()

    private(set) var account: AccountState
    private(set) var isSigningIn = false
    /// A user-facing account problem to show in an alert.
    var accountError: String?

    /// The user's id on the shared track. Friends have server ids, so a fixed
    /// local id can't collide with them.
    let currentUserID: UserID = "me"
    var timeZone: TimeZone { .current }

    init(store: LocalStore = LocalStore(), sampleFriends: FriendRepository = MockFriendRepository(),
         backend: WalkscapeBackend? = SupabaseConfig.fromBundle.map {
             WalkscapeBackend(config: $0, sessionStore: KeychainSessionStore())
         }) {
        self.store = store
        self.sampleFriends = sampleFriends
        self.backend = backend
        account = backend == nil ? .localOnly : .signedOut
        let settings = store.loadSettings()
        self.settings = settings
        let source = settings.dataSource ?? Self.defaultSource
        progression = store.loadProgression(source)
        wallet = store.loadWallet(source)
        journal = store.loadJournal(source)
        adState = store.loadAdState()
        ledger = store.loadLedger(source)
        questTracker = store.loadQuestTracker(source)
        showcase = store.loadShowcase()
        premiumLook = store.loadPremiumLook()
        seenTips = store.seenTips
        collections = store.loadCollections(source)
        notificationPreferences = store.loadNotificationPreferences(legacyReminder: settings.dailyReminderEnabled)
        notificationLedger = store.loadNotificationLedger()
        companion = Self.companion(for: source, store: store, progression: progression,
                                   today: LocalDay(date: Date(), timeZone: .current))
        companionRoster = store.loadCompanionRoster(source)
        if let saved = store.loadLastProgress(source) { sync.restore(saved) }
    }

    /// The saved companion for `source`, adopting the chosen species there
    /// (starting from that source's current lifetime) if it's new to it.
    private static func companion(for source: WalkingDataSourceKind, store: LocalStore, progression: ProgressionState,
                                  today: LocalDay) -> CompanionState? {
        guard let speciesID = store.companionSpeciesID else { return nil }
        if let saved = store.loadCompanion(source), saved.speciesID == speciesID { return saved }
        let adopted = CompanionState(speciesID: speciesID, adoptedOn: today, lifetimeMeters: progression.lifetimeMeters)
        store.save(adopted, for: source)
        return adopted
    }

    // MARK: Derived

    static var defaultSource: WalkingDataSourceKind {
        #if targetEnvironment(simulator)
        return .demo
        #else
        return HealthKitWalkingDataProvider.isAvailable ? .appleHealth : .demo
        #endif
    }

    var dataSource: WalkingDataSourceKind { settings.dataSource ?? Self.defaultSource }
    var isDemo: Bool { dataSource == .demo }
    private var provider: WalkingDataProvider { isDemo ? demoProvider : healthProvider }

    var today: LocalDay { LocalDay(date: now, timeZone: timeZone) }

    /// Today's totals, or nil if none have been fetched today.
    var todayProgress: DailyProgress? {
        guard let progress = sync.progress, progress.localDate == today else { return nil }
        return progress
    }

    var distanceMeters: Int { todayProgress?.distanceMeters ?? 0 }
    var steps: Int { todayProgress?.steps ?? 0 }
    var isDistanceEstimated: Bool { todayProgress?.isEstimated ?? false }
    var zoneProgress: ZoneProgress { engine.progress(forMeters: distanceMeters) }
    var freshness: DataFreshness { sync.freshness(now: now) }
    /// The Journey screen's sync chip.
    var healthSyncIndicator: HealthSyncIndicator {
        .evaluate(isDemo: isDemo, authorization: authorization, status: sync, now: now)
    }
    var needsHealthConnection: Bool { !isDemo && authorization == .notDetermined }
    var healthUnavailable: Bool { !isDemo && authorization == .unavailable }

    var me: TrackParticipant {
        TrackParticipant(id: currentUserID, name: "You", avatarID: settings.avatarID,
                         distanceMeters: todayProgress == nil ? 0 : distanceMeters,
                         isDistanceEstimated: isDistanceEstimated, availability: .current,
                         currentZoneID: zoneProgress.currentZone.id, updatedAt: sync.lastSuccessfulRefresh,
                         isCurrentUser: true)
    }

    var trackParticipants: [TrackParticipant] {
        [me] + friends.map(TrackParticipant.init(friend:))
    }

    var isSignedIn: Bool {
        if case .signedIn = account { return true }
        return false
    }

    /// Sample friends are only used when there is no backend.
    var usesSampleFriends: Bool { account == .localOnly }

    private var friendRepository: FriendRepository? {
        switch account {
        case .localOnly: return sampleFriends
        case .signedOut: return nil
        case .signedIn: return backend?.friends
        }
    }

    // MARK: Lifecycle

    /// Call once at launch.
    func start() {
        guard tickerTask == nil else { return }
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.tick()
            }
        }
        Task {
            await restoreSession()
            await refreshAll()
            startHealthObservationIfPossible()
        }
        startAdsIfReady()
        shop.onVerifiedTransaction = { [weak self] jws in await self?.recordPurchase(jws) }
        shop.start()
        notifications.onOpen = { [weak self] destination in self?.open(destination) }
        notifications.onDeviceToken = { [weak self] _ in Task { await self?.registerPushToken() } }
        if let destination = notifications.takePendingDestination() { open(destination) }
        Task {
            await notifications.refreshAuthorization()
            scheduleDailyReminder()
        }
    }

    /// Call when the app becomes active.
    func didBecomeActive() {
        Task { await refreshAll() }
        Task { await notifications.refreshAuthorization() }
        if let backgroundedAt {
            self.backgroundedAt = nil
            showAppOpenAdIfAllowed(timeAway: Date().timeIntervalSince(backgroundedAt))
        }
    }

    /// Call when the app goes to the background.
    func didEnterBackground() {
        if !isWatchingAd && !ads.isShowingAd { backgroundedAt = Date() }
        updateWidget()
    }

    // MARK: Widget

    private var lastWidgetSnapshot: WidgetSnapshot?

    /// Shares today's walk, the walker and the companion with the home-screen
    /// widget, and asks it to redraw when something it shows has changed.
    /// Demo data never reaches the widget.
    func updateWidget() {
        guard dataSource == .appleHealth, let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroup) else { return }
        let zone = zoneProgress
        let snapshot = WidgetSnapshot(
            avatarID: settings.avatarID, outfit: outfit, companionSpeciesID: companion?.speciesID,
            companionKilometres: companionGrowth?.kilometres ?? 0, companionAccessories: companion?.wornAccessories ?? [],
            companionSkinID: companionSkin?.id, day: today, todayMeters: distanceMeters, todaySteps: sync.progress?.steps,
            totalMeters: progression.lifetimeMeters, zoneName: zone.currentZone.name, biome: zone.currentZone.biome,
            nextZoneName: zone.nextZone.name, metersToNextZone: zone.metersToNextZone, updatedAt: now)
        if let last = lastWidgetSnapshot {
            var unchanged = snapshot
            unchanged.updatedAt = last.updatedAt
            guard unchanged != last else { return }
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WidgetSnapshot.storageKey)
        lastWidgetSnapshot = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func tick() async {
        let previousDay = today
        now = Date()
        if today != previousDay {
            // Local midnight passed: today's numbers start from zero.
            sync.rollOver(to: today)
            await refreshAll()
        } else if now.timeIntervalSince(lastAutoRefresh) > 5 * 60 {
            await refreshAll()
        }
    }

    func refreshAll() async {
        lastAutoRefresh = Date()
        rollQuests()
        async let walking: Void = refreshWalking()
        async let social: Void = refreshFriends()
        async let team: Void = refreshTeam()
        async let referrals: Void = refreshReferrals()
        async let communityGroups: Void = refreshGroups()
        _ = await (walking, social, team, referrals, communityGroups)
        await syncCloudSave()
        await refreshPurchases()
    }

    // MARK: Walking data

    func refreshWalking() async {
        let source = dataSource
        let provider = self.provider
        now = Date()
        let day = today
        sync.rollOver(to: day)
        sync.beginRefresh()

        authorization = await provider.authorizationState()
        if source == .appleHealth, authorization != .requested {
            if authorization == .unavailable { sync.fail(.healthDataUnavailable) } else { sync.cancelRefresh() }
            return
        }

        do {
            let snapshot = try await provider.fetchDailyTotals(for: day, timeZone: timeZone, now: now)
            // Ignore results from a source the user switched away from mid-fetch.
            guard source == dataSource else { return }
            sync.finish(with: snapshot, userID: currentUserID)
            guard let progress = sync.progress, progress.distanceSource != .unavailable else { return }
            store.save(lastProgress: progress, for: source)
            let event = progression.apply(progress, using: engine)
            store.save(progression, for: source)
            let coins = wallet.apply(progress)
            store.save(wallet, for: source)
            if let chests = GameNotifications.chests(coins.newChests, on: progress.localDate, total: wallet.chestsFoundToday) {
                announce([chests])
            }
            rollQuests()
            questTracker.recordChestsFound(wallet.chestsFoundToday, on: progress.localDate)
            store.save(questTracker, for: source)
            updateJournal(source: source)
            processCollections(on: progress.localDate, source: source)
            processWorldEvents(on: progress.localDate, source: source)
            processCompanionFind(on: progress.localDate, meters: progress.distanceMeters, source: source)
            processSeasonalEvents(source: source)
            processLevelUps(source: source)
            updateWidget()
            announce(questBoard.daily.filter(\.isComplete).map(GameNotifications.questComplete)
                     + (questBoard.weekly + questBoard.companion).filter(\.isComplete).map(GameNotifications.questComplete))
            if let newCelebration = event.celebration {
                celebrationCoins = coins.coinsEarned
                celebration = newCelebration
            }
            await uploadProgress(progress, source: source)
        } catch let error as WalkingDataError {
            sync.fail(error)
        } catch {
            sync.fail(.queryFailed(error.localizedDescription))
        }
    }

    func connectAppleHealth() async {
        switchDataSource(to: .appleHealth)
        do {
            try await healthProvider.requestAuthorization()
        } catch let error as WalkingDataError {
            sync.fail(error)
            return
        } catch {
            sync.fail(.authorizationFailed(error.localizedDescription))
            return
        }
        await refreshWalking()
        startHealthObservationIfPossible()
    }

    func switchDataSource(to source: WalkingDataSourceKind) {
        guard source != dataSource || settings.dataSource == nil else { return }
        settings.dataSource = source
        sync = WalkingSyncStatus()
        progression = store.loadProgression(source)
        wallet = store.loadWallet(source)
        journal = store.loadJournal(source)
        ledger = store.loadLedger(source)
        questTracker = store.loadQuestTracker(source)
        collections = store.loadCollections(source)
        discovery = nil
        companion = Self.companion(for: source, store: store, progression: progression, today: today)
        companionRoster = store.loadCompanionRoster(source)
        if let saved = store.loadLastProgress(source) { sync.restore(saved) }
        celebration = nil
        levelUp = nil
        rollQuests()
        Task { await refreshWalking() }
    }

    private func startHealthObservationIfPossible() {
        guard dataSource == .appleHealth, authorization == .requested else { return }
        healthProvider.startObservingChanges { [weak self] in
            Task { @MainActor [weak self] in await self?.refreshWalking() }
        }
    }

    /// Demo only: walk a bit further to preview zone transitions.
    func simulateWalk(meters: Int) {
        guard isDemo else { return }
        demoProvider.simulateWalk(meters: meters)
        Task { await refreshWalking() }
    }

    func resetDemoData() {
        demoProvider.setScenario(.fixed(steps: 3_180, meters: 2_400))
        progression = ProgressionState()
        store.save(progression, for: .demo)
        wallet = WalletState()
        store.save(wallet, for: .demo)
        journal = JourneyJournal()
        store.save(journal, for: .demo)
        ledger = RewardLedger()
        store.save(ledger, for: .demo)
        questTracker = QuestTracker()
        store.save(questTracker, for: .demo)
        collections = CollectionState()
        store.save(collections, for: .demo)
        store.save(nil, for: .demo)
        store.save(CompanionRoster(), for: .demo)
        companionRoster = CompanionRoster()
        companion = Self.companion(for: .demo, store: store, progression: progression, today: today)
        sync = WalkingSyncStatus()
        Task { await refreshWalking() }
    }

    // MARK: Companion & journal

    var needsCompanionChoice: Bool { companion == nil }

    // MARK: First-time tips

    /// The one tip to show on the Journey screen, if any: the first unseen tip
    /// whose moment has come, and none while a celebration is on screen.
    var journeyTip: GameTip? {
        guard !needsCompanionChoice, celebration == nil, levelUp == nil, discovery == nil, teamWorldArrival == nil else {
            return nil
        }
        let due: [(GameTip, Bool)] = [
            (.firstChest, wallet.pendingChests > 0),
            (.firstZone, progression.discoveredZoneIDs.count > 1),
            (.companionGrowth, (companionGrowth?.stage.rawValue ?? 0) > CompanionGrowth.Stage.hatchling.rawValue),
            (.firstQuest, true),
        ]
        return due.first { $0.1 && !seenTips.contains($0.0.rawValue) }?.0
    }

    func shouldShowTip(_ tip: GameTip) -> Bool { !seenTips.contains(tip.rawValue) }

    func dismissTip(_ tip: GameTip) {
        seenTips.insert(tip.rawValue)
        store.seenTips = seenTips
    }

    var companionGrowth: CompanionGrowth? { companion?.growth(lifetimeMeters: progression.lifetimeMeters) }

    func chooseCompanion(_ species: CompanionSpecies) {
        store.companionSpeciesID = species.id
        let adopted = CompanionState(speciesID: species.id, adoptedOn: today, lifetimeMeters: progression.lifetimeMeters)
        companion = adopted
        store.save(adopted, for: dataSource)
        recordInJournal([JournalEvents.adoption(of: adopted)])
        startAdsIfReady()
    }

    /// Wakes a resting companion; the one walking now goes to rest, keeping its growth.
    func swapCompanion(to speciesID: String) {
        guard let current = companion, current.speciesID != speciesID,
              let woken = companionRoster.swap(active: current, to: speciesID, lifetimeMeters: progression.lifetimeMeters,
                                               at: Date()) else { return }
        setActiveCompanion(woken)
    }

    /// Adopts another species for `CompanionRoster.adoptionCost` coins. It
    /// starts as a hatchling; the current companion rests and keeps its growth.
    /// Returns an error message, or nil on success.
    func adoptCompanion(_ species: CompanionSpecies) async -> String? {
        guard let first = companion else { return "Choose your first companion first." }
        guard companionRoster.adoptable(active: first).contains(species) else { return "You already have \(species.name)." }
        let cost = CompanionRoster.adoptionCost
        guard wallet.coins >= cost else { return "You need \(cost) coins to adopt \(species.name)." }
        if dataSource == .appleHealth {
            // The server charges it, from the cloud save.
            guard let backend, isSignedIn else { return "Sign in to adopt companions." }
            await syncCloudSave(force: true)
            do {
                let purchase = try await backend.wallet.adoptCompanion(speciesID: species.id)
                wallet.receiveServerPurchase(chargeKey: purchase.chargeKey, coins: purchase.coins, itemID: nil)
            } catch WalletService.PurchaseError.insufficientCoins, WalletService.PurchaseError.needsCloudSave {
                return "Your latest coins haven't reached the cloud yet. Try again in a moment."
            } catch WalletService.PurchaseError.notSignedIn {
                handleSessionExpired()
                return "Sign in again to adopt companions."
            } catch {
                return "Couldn't reach the server. Check your connection and try again."
            }
        } else {
            guard wallet.spend(key: CompanionRoster.adoptionChargeKey(species.id), amount: cost) else {
                return "You need \(cost) coins to adopt \(species.name)."
            }
        }
        store.save(wallet, for: dataSource)
        guard let current = companion else { return nil }
        let adopted = companionRoster.adopt(species.id, replacing: current, lifetimeMeters: progression.lifetimeMeters,
                                            on: today, at: Date())
        setActiveCompanion(adopted)
        recordInJournal([JournalEvents.adoption(of: adopted)])
        if dataSource == .appleHealth { await syncCloudSave(force: true) }
        return nil
    }

    private func setActiveCompanion(_ next: CompanionState) {
        store.companionSpeciesID = next.speciesID
        companion = next
        store.save(next, for: dataSource)
        store.save(companionRoster, for: dataSource)
        updateWidget()
        Task { await syncCloudSave(force: true) }
    }

    /// Records any new milestones. Safe to call repeatedly: entries are keyed by event.
    private func updateJournal(source: WalkingDataSourceKind) {
        var entries = JournalEvents.entries(progression: progression, catalog: engine.catalog, today: today)
        if var current = companion {
            for stage in current.newEvolutions(lifetimeMeters: progression.lifetimeMeters) {
                entries.append(JournalEvents.evolution(stage, of: current, on: today))
            }
            if current != companion {
                companion = current
                store.save(current, for: source)
            }
        }
        let added = journal.record(entries)
        if !added.isEmpty {
            store.save(journal, for: source)
            announce(GameNotifications.journal(added, on: today))
        }
    }

    private func recordInJournal(_ entries: [JournalEntry]) {
        let added = journal.record(entries)
        if !added.isEmpty {
            store.save(journal, for: dataSource)
            announce(GameNotifications.journal(added, on: today))
        }
    }

    // MARK: Day history

    /// Totals for a past (or the current) day, read without touching progression.
    struct DayRecord: Equatable {
        let day: LocalDay
        let steps: Int?
        let meters: Int?
        let isEstimated: Bool
        /// True when the numbers came straight from Apple Health.
        let fromHealth: Bool
    }

    /// How far back the World screen lets you browse.
    var historyEarliestDay: LocalDay {
        DayBrowser.earliestDay(today: today, recordedDays: progression.dailyBestMeters.keys, lookback: isDemo ? 0 : 89)
    }

    /// Reads a day's totals. Never applies them: browsing can't grant rewards
    /// or change today's journey.
    func dayRecord(for day: LocalDay) async -> DayRecord {
        let recorded = progression.dailyBestMeters[day.isoString]
        if day == today, let progress = todayProgress {
            return DayRecord(day: day, steps: progress.steps, meters: progress.distanceMeters,
                             isEstimated: progress.isEstimated, fromHealth: !isDemo)
        }
        let fallback = DayRecord(day: day, steps: nil, meters: recorded, isEstimated: false, fromHealth: false)
        guard !isDemo, authorization == .requested else { return fallback }
        do {
            let snapshot = try await healthProvider.fetchDailyTotals(for: day, timeZone: timeZone, now: Date())
            guard snapshot.steps != nil || snapshot.recordedDistanceMeters != nil else { return fallback }
            let progress = DailyProgress(snapshot: snapshot, userID: currentUserID)
            return DayRecord(day: day, steps: progress.steps, meters: progress.distanceMeters,
                             isEstimated: progress.isEstimated, fromHealth: true)
        } catch {
            return fallback
        }
    }

    // MARK: Referrals

    /// Referral rewards always go to the Apple Health wallet, whatever source is showing.
    private func updateHealthWallet(_ change: (inout WalletState) -> Void) {
        if dataSource == .appleHealth {
            change(&wallet)
            store.save(wallet, for: .appleHealth)
        } else {
            var healthWallet = store.loadWallet(.appleHealth)
            change(&healthWallet)
            store.save(healthWallet, for: .appleHealth)
        }
    }

    /// Referral chests ready to open (from the Apple Health wallet).
    var referralChests: [ReferralChest] {
        dataSource == .appleHealth ? wallet.referralChests : store.loadWallet(.appleHealth).referralChests
    }

    var pendingReferralCode: String? { store.pendingReferralCode }

    func refreshReferrals() async {
        guard let backend, isSignedIn else {
            referral = nil
            referralError = nil
            return
        }
        if let code = store.pendingReferralCode { await redeemReferral(code: code, refresh: false) }
        do {
            async let status = backend.referrals.status()
            async let ready = backend.referrals.readyChests()
            let (newStatus, chests) = try await (status, ready)
            referral = newStatus
            var alreadyOpened: [ReferralChest] = []
            var added: [ReferralChest] = []
            updateHealthWallet { wallet in
                added = wallet.receiveReferralChests(chests)
                alreadyOpened = chests.filter { wallet.openedReferralChestIDs.contains($0.id) }
            }
            announce(added.map(GameNotifications.referralChest))
            // A chest opened while offline: tell the server now.
            for chest in alreadyOpened { try? await backend.referrals.markOpened(chest) }
            referralError = nil
        } catch ReferralError.notSignedIn {
            handleSessionExpired()
        } catch {
            referralError = "Couldn't load your invites right now."
        }
    }

    /// Saves a code entered before signing in; it's redeemed once you have an account.
    func rememberReferralCode(_ code: String) {
        let clean = ReferralRules.normalize(code)
        store.pendingReferralCode = clean.isEmpty ? nil : clean
    }

    /// Uses a friend's code. Returns an error message, or nil on success.
    @discardableResult
    func redeemReferral(code: String, refresh: Bool = true) async -> String? {
        let clean = ReferralRules.normalize(code)
        guard !clean.isEmpty else { return "Enter a code." }
        guard let backend, isSignedIn else {
            store.pendingReferralCode = clean
            return nil
        }
        do {
            try await backend.referrals.redeem(code: clean)
            store.pendingReferralCode = nil
            if refresh { await refreshReferrals() }
            return nil
        } catch let error as ReferralError {
            if case .network = error { return "Couldn't check that code. Try again in a moment." }
            // Anything else is final: don't keep retrying a code that can't work.
            store.pendingReferralCode = nil
            switch error {
            case .codeNotFound: return "No walker has that code."
            case .ownCode: return "That's your own code."
            case .alreadyRedeemed: return "You've already used an invite code."
            case .accountTooOld: return "Invite codes are for accounts in their first \(ReferralRules.redeemWithinDays) days."
            case .circular: return "You invited this walker, so you can't use their code."
            case .notSignedIn: return "Sign in to use an invite code."
            case .network: return nil
            }
        } catch {
            return "Couldn't check that code."
        }
    }

    /// Opens a referral chest. Returns its coins.
    func openReferralChest(_ chest: ReferralChest) -> Int? {
        var coins: Int?
        updateHealthWallet { coins = $0.openReferralChest(id: chest.id) }
        guard let coins else { return nil }
        recordInJournal([JournalEvents.referralChest(id: chest.id, coins: coins, on: today)])
        if let backend { Task { try? await backend.referrals.markOpened(chest) } }
        return coins
    }

    // MARK: Teams

    func refreshTeam() async {
        guard let backend, isSignedIn else {
            team = nil
            teamInvites = []
            teamError = nil
            hasLoadedTeam = false
            return
        }
        isLoadingTeam = true
        defer {
            isLoadingTeam = false
            hasLoadedTeam = true
        }
        do {
            async let dashboard = backend.teams.dashboard(for: today, now: Date())
            async let invites = backend.teams.invites()
            let (newTeam, newInvites) = try await (dashboard, invites)
            team = newTeam
            teamInvites = newInvites
            teamError = nil
            announce(newInvites.map(GameNotifications.teamInvite))
            await refreshCampsite(newTeam)
            if let newTeam { recordTeamMilestones(newTeam) }
        } catch TeamRepositoryError.notSignedIn {
            handleSessionExpired()
        } catch {
            teamError = "Couldn't reach your team right now. Showing the last update."
        }
    }

    private func recordTeamMilestones(_ dashboard: TeamDashboard) {
        let entries = dashboard.badges.map { badge -> JournalEntry in
            let isExpedition = badge.id.hasPrefix("expedition-")
            // Weekly badges can be earned again each week; expeditions once per team.
            let key = isExpedition ? badge.id : "\(badge.id)-\(dashboard.weekStart.isoString)"
            let title = isExpedition ? "\(dashboard.team.name) completed \(badge.name)" : "\(dashboard.team.name): \(badge.name)"
            return JournalEntry(id: "team-\(dashboard.team.id)-\(key)", kind: isExpedition ? .expedition : .team,
                                day: today, title: title, detail: badge.detail, iconID: badge.spriteID)
        }
        recordInJournal(entries)
    }

    /// Runs a team action and refreshes. Returns an error message, or nil on success.
    private func teamAction(_ action: (TeamRepository) async throws -> Void) async -> String? {
        guard let backend, isSignedIn else { return "Sign in to use teams." }
        do {
            try await action(backend.teams)
            await refreshTeam()
            return nil
        } catch let error as TeamRepositoryError {
            switch error {
            case .teamNotFound: return "No team has that code."
            case .alreadyInTeam: return "You're already in a team. Leave it first."
            case .notInTeam: return "You're not in a team."
            case .notFriends: return "You can only invite friends."
            case .invalidName: return "Team names need 3–24 letters, numbers or spaces."
            case .insufficientCoins:
                return spendableCoins >= CreationCosts.team
                    ? "Your latest coins are still syncing. Try again in a moment."
                    : "You need \(CreationCosts.team) coins to start a team."
            case .needsCloudSave: return "Your progress hasn't reached the server yet. Try again in a moment."
            case .updateApp: return "Update Walkscape to do that."
            case .notSignedIn:
                handleSessionExpired()
                return "Please sign in again."
            case .notConfigured: return "Teams aren't set up in this build."
            case .network(let message): return message.isEmpty ? "That didn't go through." : message
            }
        } catch {
            return "That didn't go through. Check your connection and try again."
        }
    }

    /// Creates a team for `CreationCosts.team` coins. Keep `requestID` the same
    /// when retrying one attempt, so the team is made and paid for once.
    func createTeam(named name: String, requestID: UUID) async -> String? {
        guard spendableCoins >= CreationCosts.team else { return "You need \(CreationCosts.team) coins to start a team." }
        await syncCloudSave(force: true)
        let error = await teamAction { try await $0.createTeam(named: name, requestID: requestID) }
        if error == nil { await settleCharge(.team, requestID: requestID, amount: CreationCosts.team) }
        return error
    }
    func joinTeam(code: String) async -> String? { await teamAction { try await $0.joinTeam(code: code) } }
    func leaveTeam() async -> String? { await teamAction { try await $0.leaveTeam() } }
    func inviteToTeam(_ friend: UserID) async -> String? { await teamAction { try await $0.invite(friend: friend) } }
    func respond(to invite: TeamInvite, accept: Bool) async -> String? {
        await teamAction { try await $0.respond(to: invite, accept: accept) }
    }

    // MARK: Groups

    private(set) var groups: [CommunityGroup] = []
    private(set) var hasLoadedGroups = false
    private(set) var groupsError: String?

    /// Coins that can pay for creating a team or group: the Apple Health
    /// wallet, which is the one in the cloud save the server charges.
    var spendableCoins: Int { dataSource == .appleHealth ? wallet.coins : store.loadWallet(.appleHealth).coins }

    func refreshGroups() async {
        guard let backend, isSignedIn else {
            groups = []
            return
        }
        do {
            groups = try await backend.groups.myGroups()
            groupsError = nil
            hasLoadedGroups = true
        } catch {
            groupsError = groupMessage(error)
        }
    }

    /// Creates a group for `CreationCosts.group` coins and returns its id.
    /// The server checks and takes the coins with the creation; keep
    /// `requestID` the same when retrying one attempt so it's paid for once.
    func createGroup(requestID: UUID, name: String, description: String, emblem: String) async -> Result<String, GroupError> {
        guard let backend, isSignedIn else { return .failure(.notSignedIn) }
        guard spendableCoins >= CreationCosts.group else { return .failure(.insufficientCoins) }
        // The server pays from the cloud save, so bring it up to date first.
        await syncCloudSave(force: true)
        do {
            let id = try await backend.groups.createGroup(requestID: requestID, name: name, description: description, emblem: emblem)
            await settleCharge(.group, requestID: requestID, amount: CreationCosts.group)
            await refreshGroups()
            return .success(id)
        } catch let error as GroupError {
            if error == .notSignedIn { handleSessionExpired() }
            if error == .insufficientCoins, spendableCoins >= CreationCosts.group { return .failure(.needsCloudSave) }
            return .failure(error)
        } catch {
            return .failure(.network(""))
        }
    }

    /// Records a charge the server made, under its key, and syncs, so the
    /// phone shows the coins gone straight away and never pays twice.
    private func settleCharge(_ kind: CreationCosts.Kind, requestID: UUID, amount: Int) async {
        updateHealthWallet { $0.recordServerCharge(key: CreationCosts.chargeKey(kind, requestID: requestID), amount: amount) }
        await syncCloudSave(force: true)
    }

    func previewGroup(code: String) async -> Result<GroupPreview?, GroupError> {
        await groupCall { try await $0.preview(code: code) }
    }

    func joinGroup(code: String) async -> Result<String, GroupError> {
        let result = await groupCall { try await $0.join(code: code) }
        if case .success = result { await refreshGroups() }
        return result
    }

    func leaveGroup(_ group: CommunityGroup) async -> String? {
        await groupAction { try await $0.leave(groupID: group.id) }
    }

    func removeMember(_ member: GroupMember, from group: CommunityGroup) async -> String? {
        await groupAction { try await $0.remove(member: member.userID, from: group.id) }
    }

    func updateGroup(_ group: CommunityGroup, name: String, description: String, emblem: String) async -> String? {
        await groupAction { try await $0.update(groupID: group.id, name: name, description: description, emblem: emblem) }
    }

    func regenerateCode(for group: CommunityGroup) async -> Result<String, GroupError> {
        let result = await groupCall { try await $0.regenerateCode(groupID: group.id) }
        if case .success = result { await refreshGroups() }
        return result
    }

    func groupMembers(_ group: CommunityGroup, offset: Int) async -> Result<(members: [GroupMember], total: Int), GroupError> {
        await groupCall { try await $0.members(groupID: group.id, limit: GroupRules.pageSize, offset: offset) }
    }

    /// A leaderboard page for today's local date (or this week, Monday onwards).
    func groupLeaderboard(_ group: CommunityGroup, period: LeaderboardPeriod, offset: Int, limit: Int) async
        -> Result<GroupLeaderboardPage, GroupError> {
        let day = today
        return await groupCall { try await $0.leaderboard(groupID: group.id, period: period, day: day, limit: limit, offset: offset) }
    }

    private func groupCall<T>(_ body: (SupabaseGroupRepository) async throws -> T) async -> Result<T, GroupError> {
        guard let backend, isSignedIn else { return .failure(.notSignedIn) }
        do {
            return .success(try await body(backend.groups))
        } catch let error as GroupError {
            if error == .notSignedIn { handleSessionExpired() }
            return .failure(error)
        } catch {
            return .failure(.network(""))
        }
    }

    private func groupAction(_ body: (SupabaseGroupRepository) async throws -> Void) async -> String? {
        let result = await groupCall(body)
        await refreshGroups()
        if case .failure(let error) = result { return error.message }
        return nil
    }

    private func groupMessage(_ error: Error) -> String {
        (error as? GroupError)?.message ?? "Couldn't load your groups. Check your connection."
    }

    // MARK: Shop

    /// The walker's current outfit, in draw order.
    var outfit: [String] { wallet.outfit }

    /// Opens one chest found on today's walk. Returns the coins it held.
    func openChest() -> Int? {
        // Each chest has a permanent id; opening the same one again pays nothing.
        guard let id = wallet.pendingChestIDs.first else { return nil }
        let coins = wallet.openChest(id: id)
        store.save(wallet, for: dataSource)
        if coins != nil {
            rollQuests()
            questTracker.recordChestOpened()
            store.save(questTracker, for: dataSource)
            // Now and then a chest also holds a treasure. The roll is fixed per
            // chest, so reopening the app can't re-roll it.
            let seed = "chest#\(id)"
            if WildlifeCatalog.roll(seed) < TreasureCatalog.chestTreasureChance {
                awardTreasure(seed: seed)
            }
        }
        return coins
    }

    /// Opens a Mystery Box: the only way to get outfits and companion accessories.
    /// With Apple Health data the server sells and rolls it (paid from the
    /// cloud save, so that's synced first); demo walking rolls on the phone.
    func openMysteryBox() async -> MysteryBoxResult {
        guard dataSource == .appleHealth else { return revealBoxPrize(wallet.openMysteryBox(on: today)) }
        let price = ShopCatalog.mysteryBoxPrice
        guard wallet.coins >= price else { return .notEnoughCoins(needed: price - wallet.coins) }
        guard let backend, isSignedIn else { return .unavailable("Sign in to open Mystery Boxes.") }
        await syncCloudSave(force: true)
        do {
            let purchase = try await backend.wallet.openMysteryBox(requestID: UUID(), day: today)
            wallet.receiveServerPurchase(chargeKey: purchase.chargeKey, coins: purchase.coins, itemID: purchase.itemID)
            store.save(wallet, for: .appleHealth)
            await syncCloudSave(force: true)
            guard let prize = purchase.itemID.flatMap(MysteryBox.prize(withID:)) else {
                return .unavailable("Your prize is in your collection. Update the app to see it.")
            }
            return revealBoxPrize(.won(prize))
        } catch WalletService.PurchaseError.soldOut {
            return .soldOut
        } catch WalletService.PurchaseError.insufficientCoins, WalletService.PurchaseError.needsCloudSave {
            return .unavailable("Your latest coins haven't reached the cloud yet. Try again in a moment.")
        } catch WalletService.PurchaseError.notSignedIn {
            handleSessionExpired()
            return .unavailable("Sign in again to open Mystery Boxes.")
        } catch {
            return .unavailable("Couldn't reach the Mystery Box. Check your connection and try again.")
        }
    }

    /// A new accessory goes straight on if that slot is free.
    private func revealBoxPrize(_ result: MysteryBoxResult) -> MysteryBoxResult {
        store.save(wallet, for: dataSource)
        if case .won(.accessory(let accessory, _)) = result, var current = companion,
           !current.wornAccessories.contains(where: { CompanionAccessoryCatalog.accessory(withID: $0)?.slot == accessory.slot }) {
            current.toggle(accessory)
            companion = current
            store.save(current, for: dataSource)
        }
        return result
    }

    func toggleEquipped(_ item: ShopItem) {
        if wallet.isEquipped(item) { wallet.unequip(item.slot) } else { wallet.equip(item) }
        store.save(wallet, for: dataSource)
        // Friends see what you wear.
        if dataSource == .appleHealth { Task { await publishShowcase() } }
        updateWidget()
    }

    // MARK: Explorer level

    var explorerXP: ExplorerXP { ExplorerXP(progression: progression, ledger: ledger) }
    var explorerLevel: ExplorerLevel { ExplorerLevel(totalXP: explorerXP.total) }

    /// Pays and celebrates any levels reached since the last check. Safe to
    /// call after every refresh: each level is paid once (see `RewardLedger`).
    private func processLevelUps(source: WalkingDataSourceKind) {
        let levels = ledger.levelUps(totalXP: explorerXP.total, into: &wallet)
        guard let top = levels.last else { return }
        // Some levels also give a companion accessory.
        for level in levels {
            let gifts = CompanionAccessoryCatalog.unlocked(atLevel: level).map(\.id)
            if !gifts.isEmpty { ledger.claim(Reward(id: "level-\(level)-companion", itemIDs: gifts), into: &wallet) }
        }
        store.save(ledger, for: source)
        store.save(wallet, for: source)
        // One entry and one banner, even if several levels arrived at once.
        recordInJournal([JournalEvents.levelUp(to: top, on: today)])
        levelUp = top
    }

    /// Grants a reward once. Returns false if it was already claimed.
    @discardableResult
    func claim(_ reward: Reward) -> Bool {
        guard ledger.claim(reward, into: &wallet) else { return false }
        store.save(ledger, for: dataSource)
        store.save(wallet, for: dataSource)
        processLevelUps(source: dataSource)
        return true
    }

    // MARK: Campfire

    private func refreshCampsite(_ dashboard: TeamDashboard?) async {
        guard let backend, let dashboard else {
            campsite = nil
            teamContributions = []
            return
        }
        let placed = (try? await backend.teams.campsiteDecorations()) ?? campsite?.decorations ?? []
        if let contributions = try? await backend.teams.contributions() { teamContributions = contributions }
        // Older servers without the unlock table fall back to the app's own calculation.
        let serverUnlocks = try? await backend.teams.recordTeamWorldUnlocks()
        let site = Campsite(teamMeters: dashboard.team.totalMeters, expeditions: dashboard.expeditions.completed.count,
                            placed: placed)
        campsite = site
        // Level rewards are per player, so moving teams can't collect them twice.
        guard dataSource == .appleHealth else { return }
        processTeamWorlds(dashboard, serverUnlocks: serverUnlocks)
        processWaypointChallenge(dashboard)
        for level in CampfireCatalog.levels where level.level > 1 && level.level <= site.level.level {
            if claim(level.reward) {
                recordInJournal([JournalEvents.campfire(level, teamName: dashboard.team.name, on: today)])
            }
        }
    }

    // MARK: Team map

    /// The challenge at the team's latest 5 km stop, if it has reached one.
    func waypointChallenge(for dashboard: TeamDashboard) -> WaypointChallenge? {
        let stop = TeamMap.reachedWaypoint(teamMeters: dashboard.team.totalMeters)
        guard stop >= 1 else { return nil }
        return WaypointChallenge(waypoint: stop, teamID: dashboard.team.id, memberCount: dashboard.members.count)
    }

    /// Pays the stop's challenge to a player who walked today once the team completes it.
    private func processWaypointChallenge(_ dashboard: TeamDashboard) {
        guard let challenge = waypointChallenge(for: dashboard),
              challenge.isComplete(todayMeters: dashboard.members.map(\.dayMeters)),
              (dashboard.members.first(where: \.isCurrentUser)?.dayMeters ?? 0) >= WaypointChallenge.participationMeters,
              claim(challenge.reward) else { return }
        recordInJournal([JournalEvents.waypointChallenge(challenge, teamName: dashboard.team.name, on: today)])
        discovery = DiscoveryNews(waypoint: challenge, teamName: dashboard.team.name)
    }

    // MARK: Team worlds

    /// The newest team-world zone reached, shown full screen once.
    var teamWorldArrival: TeamWorldArrival?

    var teamWorldProgress: TeamWorldProgress? { team.map { TeamWorldProgress(teamMeters: $0.team.totalMeters) } }

    /// What the player has walked for their current team.
    var myTeamContribution: Int {
        guard let me = team?.members.first(where: \.isCurrentUser)?.id else { return 0 }
        return teamContributions.first { $0.userID == me }?.meters ?? 0
    }

    /// Zones and challenges the team has reached pay each player once, ever,
    /// and only players who have walked for the team themselves. Once the server
    /// keeps the team's unlocks, a zone pays only after it's on record there.
    private func processTeamWorlds(_ dashboard: TeamDashboard, serverUnlocks: Set<String>?) {
        let progress = TeamWorldProgress(teamMeters: dashboard.team.totalMeters)
        guard progress.isUnlocked, myTeamContribution >= TeamWorldCatalog.minimumContribution else { return }
        var newestZone: (TeamWorldZone, TeamWorld)?
        for world in TeamWorldCatalog.worlds {
            for zone in progress.reachedZones(in: world) where serverUnlocks?.contains(zone.id) ?? true {
                guard claim(zone.reward) else { continue }
                recordInJournal([JournalEvents.teamWorldZone(zone, world: world, teamName: dashboard.team.name, on: today)])
                newestZone = (zone, world)
            }
            let weekMeters = dashboard.members.compactMap(\.weekMeters).reduce(0, +)
            if progress.challengeOpen(in: world), weekMeters >= world.challenge.weekMeters, claim(world.challengeReward) {
                recordInJournal([JournalEvents.teamWorldChallenge(world, teamName: dashboard.team.name, on: today)])
            }
        }
        // Only walkers who are out today spot the world's wildlife.
        if distanceMeters >= TeamWorldCatalog.sightingMinimumMeters {
            let fresh = collections.recordSightings(TeamWorldContent.sightings(on: today, progress: progress), on: today)
            if !fresh.isEmpty {
                store.save(collections, for: .appleHealth)
                for creature in fresh { claim(creature.reward) }
                recordInJournal(fresh.map { JournalEvents.wildlife($0, on: today) })
                discovery = DiscoveryNews(creatures: fresh)
            }
        }
        for world in TeamWorldCatalog.worlds {
            let quests = world.quests(progress: progress, seenCreatures: Set(collections.wildlife.keys),
                                      challengeDone: ledger.hasClaimed(world.challengeReward.id))
            for quest in quests where quest.kind != .together && quest.isComplete && claim(quest.reward) {
                if let treasure = quest.treasure, collections.recordTreasure(treasure, on: today) {
                    store.save(collections, for: .appleHealth)
                    claim(treasure.reward)
                    discovery = DiscoveryNews(treasure: treasure)
                }
                recordInJournal([JournalEvents.teamWorldQuest(quest, world: world, on: today)])
            }
        }
        if let newest = newestZone {
            teamWorldArrival = TeamWorldArrival(zone: newest.0, world: newest.1, teamName: dashboard.team.name)
        }
    }

    func setCampsiteDecorations(_ decorations: [String]) async -> String? {
        guard let backend, let site = campsite, let team else { return "Join a team first." }
        let valid = CampfireCatalog.valid(decorations, at: site.level)
        do {
            try await backend.teams.setCampsiteDecorations(valid)
            campsite = Campsite(teamMeters: site.teamMeters, expeditions: site.expeditions, placed: valid)
            _ = team
            return nil
        } catch {
            return "Couldn't update the campsite. Check your connection."
        }
    }

    // MARK: Social

    /// Shares today's special finds and milestones, then collects shared
    /// discoveries, the friends' milestone feed and distance walked together.
    /// Only Apple Health progress is shared; demo walking stays private.
    private func refreshSocial() async {
        guard let backend, isSignedIn else { milestoneFeed = []; return }
        if dataSource == .appleHealth {
            let reachedCount = min(progression.todayHighestZoneIndex + 1, engine.catalog.zones.count)
            let reached = engine.catalog.zones.prefix(reachedCount).map(\.id)
            let finds = SharedDiscoveries.records(on: today, zonesReached: progression.day == today ? reached : [],
                                                  foundEvents: todaysEvents.filter(hasFound))
            try? await backend.social.record(discoveries: finds)
            try? await backend.social.record(milestones: FriendMilestoneCatalog.milestones(in: journal))

            if let shared = try? await backend.social.sharedDiscoveries(since: today.adding(days: -7)) {
                for found in shared where claim(found.reward) {
                    recordInJournal([found.journalEntry])
                    discovery = DiscoveryNews(shared: found)
                }
            }
            if let together = try? await backend.social.walkedTogether() {
                for friend in together {
                    for reward in WalkedTogether.rewards(friendID: friend.friendID, meters: friend.meters) where claim(reward) {
                        let km = Int(reward.id.split(separator: "-")[1].dropLast()) ?? 100
                        recordInJournal([WalkedTogether.journalEntry(friendName: friend.username, friendID: friend.friendID,
                                                                     meters: km * 1_000, on: today)])
                    }
                }
            }
        }
        if let feed = try? await backend.social.milestoneFeed(since: today.adding(days: -14)) { milestoneFeed = feed }
        for run in activeEventRuns {
            if let meters = try? await backend.social.communityDistance(from: run.startDay, to: run.endDay) {
                communityMeters[run.id] = meters
            }
        }
        processSeasonalEvents(source: dataSource)
    }

    func react(to milestone: FriendMilestone, with reaction: Reaction) async {
        guard let backend, isSignedIn else { return }
        try? await backend.social.react(to: milestone, with: reaction)
        if let feed = try? await backend.social.milestoneFeed(since: today.adding(days: -14)) { milestoneFeed = feed }
    }

    // MARK: Companion life

    /// What the companion is saying right now.
    var companionLine: String {
        guard let companion else { return "" }
        let situation: CompanionVoice.Situation
        if let celebration { situation = .newZone(celebration.zone.name) }
        else if let levelUp { situation = .levelUp(levelUp) }
        else { situation = distanceMeters > 0 ? .walking : .resting }
        return CompanionVoice.line(speciesID: companion.speciesID, situation: situation, day: today)
    }

    /// Now and then the companion finds something on the walk, in its own way.
    private func processCompanionFind(on day: LocalDay, meters: Int, source: WalkingDataSourceKind) {
        guard day == today, let companion,
              let find = CompanionPersonality.find(speciesID: companion.speciesID, day: day, metersToday: meters,
                                                   ownedTreasures: Set(collections.treasures.keys),
                                                   seenCreatures: Set(collections.wildlife.keys)),
              ledger.claim(find.reward, into: &wallet) else { return }
        if let treasure = find.treasure, collections.recordTreasure(treasure, on: day) {
            _ = ledger.claim(treasure.reward, into: &wallet)
            recordInJournal([JournalEvents.treasure(treasure, on: day)])
        }
        if let creature = find.creature, !collections.recordSightings([creature], on: day).isEmpty {
            _ = ledger.claim(creature.reward, into: &wallet)
            recordInJournal([JournalEvents.wildlife(creature, on: day)])
        }
        store.save(collections, for: source)
        store.save(ledger, for: source)
        store.save(wallet, for: source)
        recordInJournal([JournalEvents.companionFind(find)])
        discovery = DiscoveryNews(find: find)
    }

    func toggleAccessory(_ accessory: CompanionAccessory) {
        guard wallet.owns(itemID: accessory.id), var current = companion else { return }
        current.toggle(accessory)
        companion = current
        store.save(current, for: dataSource)
    }

    // MARK: Store

    /// Everything owned: this Apple ID's purchases plus what the server has
    /// verified for the account (e.g. bought on another phone).
    var entitlements: Entitlements {
        var combined = shop.entitlements
        combined.bundles.formUnion(serverEntitlements.bundles)
        if let server = serverEntitlements.plusExpires {
            combined.plusExpires = max(combined.plusExpires ?? server, server)
        }
        return combined
    }

    var hasPlus: Bool { entitlements.hasPlus(at: now) }

    /// The premium look with anything no longer owned removed.
    var currentLook: PremiumLook { premiumLook.validated(entitlements: entitlements, now: now) }

    var companionSkin: CompanionSkin? { CompanionSkinCatalog.skin(withID: currentLook.companionSkinID) }

    func buy(_ product: StoreProduct) async -> StoreService.PurchaseOutcome {
        let accountID = await backend?.auth.currentSession.flatMap { UUID(uuidString: $0.userID.rawValue) }
        let outcome = await shop.purchase(product, accountID: accountID)
        if outcome == .purchased { applyEntitlements() }
        return outcome
    }

    func restorePurchases() async -> String? {
        let error = await shop.restore()
        await refreshPurchases()
        return error
    }

    private func recordPurchase(_ jws: String) async {
        guard let backend, isSignedIn else { return }
        try? await backend.purchases.verify(signedTransaction: jws)
    }

    private func refreshPurchases() async {
        if let backend, isSignedIn, let verified = try? await backend.purchases.entitlements() {
            serverEntitlements = verified
        }
        applyEntitlements()
    }

    /// Bundle outfit pieces live in the wallet so they wear like any item;
    /// a refunded bundle takes them back. Plus members get the monthly gift.
    private func applyEntitlements() {
        guard dataSource == .appleHealth else { return }
        let owned = entitlements
        var changed = false
        for bundle in StoreCatalog.bundles {
            let outfits = bundle.contents.filter { id in PremiumOutfits.items.contains { $0.id == id } }
            guard !outfits.isEmpty else { continue }
            if owned.bundles.contains(bundle.id) {
                wallet.receiveReward(id: bundle.id, coins: 0, itemIDs: outfits)
                changed = true
            } else if outfits.contains(where: wallet.owns(itemID:)) {
                wallet.removeItems(outfits)
                changed = true
            }
        }
        if owned.hasPlus(at: now), ledger.claim(PlusMonthlyGift.reward(for: today), into: &wallet) {
            store.save(ledger, for: .appleHealth)
            changed = true
        }
        if changed { store.save(wallet, for: .appleHealth) }
    }

    // MARK: Seasonal events

    var activeEventRuns: [EventRun] { SeasonalEventCatalog.active(on: today) }
    var nextEventRun: EventRun? { SeasonalEventCatalog.next(after: today) }

    func eventProgress(_ run: EventRun) -> EventProgress {
        EventProgress(run: run, progression: progression, collections: collections)
    }

    /// Pays event tiers, quests and the community reward as they're reached.
    /// Ids include the event and year, so every run pays once.
    private func processSeasonalEvents(source: WalkingDataSourceKind) {
        for run in activeEventRuns {
            let progress = eventProgress(run)
            for (index, _) in run.event.tiers.enumerated() where index < progress.tiersReached {
                if ledger.claim(run.tierReward(index), into: &wallet) {
                    recordInJournal([JournalEvents.eventTier(run, tier: index + 1, on: today)])
                    discovery = DiscoveryNews(eventTier: run, tier: index + 1)
                }
            }
            // Plus members get the festival's accessories from the first tier.
            if hasPlus, progress.tiersReached >= 1 {
                let items = run.event.tiers.flatMap(\.itemIDs)
                if !items.isEmpty { _ = ledger.claim(Reward(id: "event-\(run.id)-plus", itemIDs: items), into: &wallet) }
            }
            for quest in run.event.quests where progress.progress(of: quest) >= quest.target {
                _ = ledger.claim(run.questReward(quest), into: &wallet)
            }
            if let total = communityMeters[run.id], total >= run.event.communityGoalKilometres * 1_000,
               progress.meters >= EventRun.communityShareMeters {
                _ = ledger.claim(run.communityReward, into: &wallet)
            }
        }
        store.save(ledger, for: source)
        store.save(wallet, for: source)
    }

    // MARK: Seasons and world events

    var season: Season { Season.of(today, southernHemisphere: Season.isSouthernHemisphere(timeZone)) }

    /// Today's events across the world (the same for every player).
    var todaysEvents: [ScheduledEvent] {
        WorldEventCatalog.schedule(for: today, season: season, exploredZoneIDs: progression.discoveredZoneIDs)
    }

    func hasFound(_ scheduled: ScheduledEvent) -> Bool { ledger.hasClaimed(scheduled.id) }

    /// Finds today's events in the zones walked through today. Each pays once
    /// (by event and day), so reopening the app never repeats one.
    private func processWorldEvents(on day: LocalDay, source: WalkingDataSourceKind) {
        guard day == today else { return }
        let reachedCount = min(progression.todayHighestZoneIndex + 1, engine.catalog.zones.count)
        let reached = Set(engine.catalog.zones.prefix(reachedCount).map(\.id))
        let hour = Calendar.current.component(.hour, from: now)
        for scheduled in todaysEvents where reached.contains(scheduled.zoneID) && scheduled.event.isOpen(season: season, hour: hour) {
            guard ledger.claim(scheduled.reward, into: &wallet) else { continue }
            let zoneName = engine.catalog.zones.first { $0.id == scheduled.zoneID }?.name ?? "the world"
            recordInJournal([JournalEvents.worldEvent(scheduled, zoneName: zoneName)])
            switch scheduled.event.bonus {
            case .none:
                discovery = DiscoveryNews(event: scheduled.event, zoneName: zoneName)
            case .creature(let id):
                if let creature = WildlifeCatalog.creature(withID: id),
                   !collections.recordSightings([creature], on: day).isEmpty {
                    store.save(collections, for: source)
                    _ = ledger.claim(creature.reward, into: &wallet)
                    recordInJournal([JournalEvents.wildlife(creature, on: day)])
                }
                discovery = DiscoveryNews(event: scheduled.event, zoneName: zoneName)
            case .treasure:
                awardTreasure(seed: scheduled.id)
            case .merchantGift(let maxRarity):
                let unowned = ShopCatalog.items.filter { !wallet.owns($0) && $0.rarity <= maxRarity }
                if !unowned.isEmpty {
                    let item = unowned[Int(WildlifeCatalog.roll(scheduled.id) * Double(unowned.count)) % unowned.count]
                    _ = ledger.claim(Reward(id: "\(scheduled.id)-gift", itemIDs: [item.id]), into: &wallet)
                }
                discovery = DiscoveryNews(event: scheduled.event, zoneName: zoneName)
            }
        }
        store.save(ledger, for: source)
        store.save(wallet, for: source)
    }

    // MARK: Collections

    /// Spots wildlife in the zones reached today and records new postcards.
    /// Every grant goes through the ledger, so refreshes never repeat one.
    private func processCollections(on day: LocalDay, source: WalkingDataSourceKind) {
        guard day == today else { return }
        let reachedCount = min(progression.todayHighestZoneIndex + 1, engine.catalog.zones.count)
        let reached = engine.catalog.zones.prefix(reachedCount).map(\.id)
        let fresh = collections.recordSightings(WildlifeCatalog.sightings(on: day, zonesReached: reached), on: day)
        if !fresh.isEmpty {
            store.save(collections, for: source)
            for creature in fresh { _ = ledger.claim(creature.reward, into: &wallet) }
            recordInJournal(fresh.map { JournalEvents.wildlife($0, on: day) })
            discovery = DiscoveryNews(creatures: fresh)
        }
        for (id, earnedOn) in Postcards.earned(in: progression) {
            guard let postcard = PostcardCatalog.postcard(withID: id), ledger.claim(postcard.reward, into: &wallet) else { continue }
            recordInJournal([JournalEvents.postcard(postcard, on: earnedOn)])
        }
        store.save(ledger, for: source)
        store.save(wallet, for: source)
    }

    private func awardTreasure(seed: String) {
        guard let treasure = TreasureCatalog.pick(seed: seed, excluding: Set(collections.treasures.keys)),
              collections.recordTreasure(treasure, on: today) else { return }
        store.save(collections, for: dataSource)
        claim(treasure.reward)
        recordInJournal([JournalEvents.treasure(treasure, on: today)])
        discovery = DiscoveryNews(treasure: treasure)
    }

    var collectionProgress: [CollectionProgress] {
        [CollectionProgress(category: .relics, found: progression.collectedItemIDs.count,
                            total: engine.catalog.allCollectibles.count),
         CollectionProgress(category: .wildlife, found: collections.trailWildlifeCount, total: WildlifeCatalog.all.count),
         CollectionProgress(category: .postcards, found: Postcards.earned(in: progression).count, total: PostcardCatalog.all.count),
         CollectionProgress(category: .treasures, found: collections.trailTreasureCount, total: TreasureCatalog.all.count),
         CollectionProgress(category: .memories, found: MemoryCatalog.reached(in: progression).count, total: MemoryCatalog.all.count)]
    }

    /// Completion rewards (25/50/75/100 % of a book) waiting to be claimed.
    var claimableCollectionRewards: [Reward] {
        collectionProgress.flatMap(\.milestoneRewards).filter { !ledger.hasClaimed($0.id) }
    }

    func claimCollectionRewards() -> Int {
        let rewards = claimableCollectionRewards
        rewards.forEach { claim($0) }
        return rewards.reduce(0) { $0 + $1.coins }
    }

    // MARK: Titles and profile

    /// Unlocks always come from Apple Health progress, so demo walking can't unlock titles.
    var profileFacts: ProfileFacts {
        let health = healthCloudSave()
        let level = ExplorerLevel(totalXP: ExplorerXP(progression: health.progression, ledger: health.ledger).total).level
        let stage = health.companion.map { max($0.celebratedStage, $0.growth(lifetimeMeters: health.progression.lifetimeMeters).stage.rawValue) }
        return ProfileFacts(progression: health.progression, explorerLevel: level, ledger: health.ledger,
                            journal: health.journal, companionStage: stage, collections: health.collections ?? CollectionState(),
                            hasPlus: hasPlus)
    }

    /// The showcase with anything not (or no longer) unlocked replaced by defaults.
    var currentShowcase: ProfileShowcase { showcase.validated(with: profileFacts) }

    /// The title shown under someone's name, if they picked one.
    func titleName(for id: UserID) -> String? {
        if id == currentUserID { return TitleCatalog.title(withID: currentShowcase.titleID)?.name }
        return friendShowcases[id]?.titleName
    }

    func frame(for id: UserID) -> ProfileFrame {
        if id == currentUserID { return FrameCatalog.frame(withID: currentShowcase.frameID) }
        return FrameCatalog.frame(withID: friendShowcases[id]?.frameID)
    }

    /// What someone on the friend track is wearing: your own outfit, or what a
    /// friend or teammate shared.
    func outfit(for id: UserID) -> [String] {
        if id == currentUserID { return outfit }
        return friendShowcases[id]?.outfit ?? []
    }

    private func publishShowcase() async {
        guard let backend, isSignedIn else { return }
        try? await backend.showcases.publish(currentShowcase)
        try? await backend.showcases.publish(outfit: outfit)
    }

    // MARK: Quests

    /// Starts a new day or week of quests when needed. Safe to call often.
    private func rollQuests() {
        let before = questTracker
        let stage = companion.map { $0.growth(lifetimeMeters: progression.lifetimeMeters).stage.rawValue }
        questTracker.roll(to: today, context: questContext, wallet: wallet, companionStage: stage)
        if questTracker != before { store.save(questTracker, for: dataSource) }
    }

    private var questContext: QuestContext {
        let expedition = team?.expeditions
        return QuestContext(
            hasFriends: !friends.isEmpty,
            inTeam: team != nil,
            hasCompanion: companion != nil,
            zonesLeftToDiscover: engine.catalog.zones.filter { !progression.discoveredZoneIDs.contains($0.id) }.count,
            metersLeftInExpedition: expedition?.current.map { $0.goalMeters - (expedition?.metersIntoCurrent ?? 0) },
            companionKilometresToNextStage: companion?.growth(lifetimeMeters: progression.lifetimeMeters).kilometresToNextStage)
    }

    var questBoard: QuestBoard {
        let facts = QuestFacts.make(
            today: today, steps: steps, meters: distanceMeters, progression: progression, wallet: wallet, journal: journal,
            tracker: questTracker,
            friendWalkedToday: friends.contains { $0.progressAvailability != .unavailable && ($0.dailyDistanceMeters ?? 0) > 0 },
            teamMetersThisWeek: team?.members.compactMap(\.weekMeters).reduce(0, +) ?? 0,
            companionStage: companion.map { $0.growth(lifetimeMeters: progression.lifetimeMeters).stage.rawValue })
        return QuestBoard(tracker: questTracker, facts: facts, ledger: ledger)
    }

    /// Claims a finished quest. Returns the reward, or nil if it isn't claimable.
    @discardableResult
    func claimQuest(_ status: QuestStatus) -> Reward? {
        guard status.isClaimable, claim(status.reward) else { return nil }
        return status.reward
    }

    /// Opens the weekly chest once every weekly quest is claimed.
    @discardableResult
    func claimWeeklyChest() -> Reward? {
        let board = questBoard
        guard board.weeklyChestReady, claim(board.weeklyChest) else { return nil }
        recordInJournal([JournalEvents.weeklyChest(week: board.week, on: today)])
        awardTreasure(seed: "week#\(board.week.isoString)")
        return board.weeklyChest
    }

    // MARK: Cloud save

    /// Merges this phone's Apple Health progress with the account's cloud save
    /// and stores the result in both places. Runs at most every two minutes
    /// unless forced (signing in). Demo data never leaves the phone.
    func syncCloudSave(force: Bool = false) async {
        guard let backend, isSignedIn, !isSyncingCloud,
              force || Date().timeIntervalSince(lastCloudSync) > 120,
              let accountID = await backend.auth.currentSession?.userID.rawValue else { return }
        isSyncingCloud = true
        defer { isSyncingCloud = false }

        // Progress on this phone that was already saved to a *different*
        // account stays with that account; this one starts from its own save.
        let localBelongsToAnother = store.cloudSaveOwner.map { $0 != accountID } ?? false
        let local = localBelongsToAnother ? freshCloudSave() : healthCloudSave()
        do {
            let merged = try await backend.cloudSave.sync(local)
            lastCloudSync = Date()
            store.cloudSaveOwner = accountID
            apply(merged)
        } catch {
            // Offline or a save from a newer app version: keep playing locally, retry later.
        }
    }

    private func healthCloudSave() -> CloudSave {
        let isHealth = dataSource == .appleHealth
        return CloudSave(progression: isHealth ? progression : store.loadProgression(.appleHealth),
                         wallet: isHealth ? wallet : store.loadWallet(.appleHealth),
                         journal: isHealth ? journal : store.loadJournal(.appleHealth),
                         ledger: isHealth ? ledger : store.loadLedger(.appleHealth),
                         companion: isHealth ? companion : store.loadCompanion(.appleHealth),
                         showcase: showcase,
                         collections: isHealth ? collections : store.loadCollections(.appleHealth),
                         companionRoster: isHealth ? companionRoster : store.loadCompanionRoster(.appleHealth),
                         savedAt: Date())
    }

    private func freshCloudSave() -> CloudSave {
        CloudSave(progression: ProgressionState(), wallet: WalletState(), journal: JourneyJournal(),
                  ledger: RewardLedger(), companion: nil, savedAt: .distantPast)
    }

    private func apply(_ save: CloudSave) {
        store.save(save.progression, for: .appleHealth)
        store.save(save.wallet, for: .appleHealth)
        store.save(save.journal, for: .appleHealth)
        store.save(save.ledger, for: .appleHealth)
        if let companion = save.companion {
            store.save(companion, for: .appleHealth)
            store.companionSpeciesID = companion.speciesID
        }
        store.save(save.companionRoster ?? CompanionRoster(), for: .appleHealth)
        guard dataSource == .appleHealth else { return }
        progression = save.progression
        wallet = save.wallet
        journal = save.journal
        ledger = save.ledger
        if let restored = save.companion { companion = restored }
        companionRoster = save.companionRoster ?? CompanionRoster()
        if let restored = save.showcase, restored != showcase { showcase = restored }
        if let restored = save.collections {
            store.save(restored, for: .appleHealth)
            if dataSource == .appleHealth { collections = restored }
        }
        processLevelUps(source: .appleHealth)
    }

    // MARK: Notifications

    /// Records events as announced and, while the app is in the background,
    /// shows the ones the player wants. Events seen in the app (it's open)
    /// are only recorded, so they are never announced later either.
    private func announce(_ events: [GameNotification]) {
        let fresh = notificationLedger.unannounced(events)
        guard !fresh.isEmpty else { return }
        store.save(notificationLedger)
        guard UIApplication.shared.applicationState != .active else { return }
        notifications.post(fresh.filter { event in
            guard notificationPreferences.allows(event.category) else { return false }
            // With a push token on the server, social news arrives as a push instead.
            return event.category != .social || notifications.deviceToken == nil || !isSignedIn
        })
    }

    /// Asks iOS for permission. Returns whether notifications are now allowed.
    func enableNotifications() async -> Bool {
        let allowed = await notifications.requestPermission()
        scheduleDailyReminder()
        return allowed
    }

    private func scheduleDailyReminder() {
        let species = companion.flatMap { CompanionCatalog.species(withID: $0.speciesID) }
        notifications.scheduleDailyReminder(
            notificationPreferences.dailyReminder ? GameNotifications.dailyReminder(companionName: species?.name) : nil,
            hour: notificationPreferences.reminderHour)
    }

    /// Sends this device's push token to the server, so friend requests and
    /// team invites can be pushed with the app closed.
    private func registerPushToken() async {
        guard let backend, isSignedIn, let token = notifications.deviceToken else { return }
        try? await backend.push.register(token: token, environment: NotificationService.pushEnvironment,
                                         social: notificationPreferences.social)
    }

    private func open(_ destination: GameNotification.Destination) {
        switch destination {
        case .journey: selectedTab = .journey
        case .friends: selectedTab = .friends
        case .shop: selectedTab = .shop
        case .profile: selectedTab = .profile
        }
    }

    // MARK: Ads

    var rewardedAdsLeft: Int { adState.rewardedAdsLeft(on: today) }

    /// Consent prompts wait until the companion is chosen, so the first
    /// thing a new player sees is the game.
    private func startAdsIfReady() {
        guard !adsStarted, !needsCompanionChoice else { return }
        adsStarted = true
        let launchedAt = Date()
        Task {
            await ads.start()
            // On a cold launch, only show the ad if it was ready quickly,
            // so it never interrupts someone who has already started playing.
            if Date().timeIntervalSince(launchedAt) < 6 { showAppOpenAdIfAllowed(timeAway: nil) }
        }
    }

    private func showAppOpenAdIfAllowed(timeAway: TimeInterval?) {
        let now = Date()
        guard ads.canRequestAds, !isWatchingAd, celebration == nil,
              adState.mayShowAppOpenAd(now: now, timeAway: timeAway, isOnboarded: !needsCompanionChoice),
              ads.presentAppOpenAd() else { return }
        adState.recordAppOpenAd(at: now)
        store.save(adState)
    }

    /// Plays a rewarded ad. Returns the coins earned, or nil if it wasn't
    /// finished, failed to load, or today's limit is used up. Coins go to the
    /// Apple Health wallet, like referral rewards.
    func watchRewardedAd() async -> Int? {
        guard rewardedAdsLeft > 0, !isWatchingAd else { return nil }
        isWatchingAd = true
        defer { isWatchingAd = false }
        // AdMob tells our server about the ad too (server-side verification),
        // under the same reward id the coins are stored under.
        let rewardID = UUID().uuidString.lowercased()
        var accountID: String?
        if isSignedIn { accountID = await backend?.auth.currentSession?.userID.rawValue }
        guard await ads.presentRewardedAd(accountID: accountID, rewardID: rewardID),
              let coins = adState.recordRewardedAd(on: today) else { return nil }
        store.save(adState)
        updateHealthWallet { $0.earnAdReward(coins, id: rewardID) }
        return coins
    }

    // MARK: Friends

    func refreshFriends() async {
        guard let friendRepository else {
            friends = []
            friendRequests = FriendRequests()
            friendsError = nil
            trackFocus.reconcile(with: trackParticipants)
            return
        }
        isLoadingFriends = true
        defer { isLoadingFriends = false }
        do {
            async let summaries = friendRepository.friendSummaries(for: today, now: Date())
            async let requests = friendRepository.friendRequests()
            (friends, friendRequests) = try await (summaries, requests)
            friendsError = nil
            announce(friendRequests.incoming.map(GameNotifications.friendRequest))
            if let backend, isSignedIn, let showcases = try? await backend.showcases.friends() { friendShowcases = showcases }
            await refreshSocial()
            trackFocus.reconcile(with: trackParticipants)
        } catch FriendRepositoryError.notSignedIn {
            handleSessionExpired()
        } catch {
            friendsError = "Couldn't reach your friends right now. Showing the last update."
        }
    }

    /// Returns a user-facing error message, or nil on success.
    func sendFriendRequest(to username: String) async -> String? {
        guard let friendRepository else { return "Sign in to add friends." }
        do {
            try await friendRepository.sendFriendRequest(toUsername: username)
            await refreshFriends()
            return nil
        } catch let error as FriendRepositoryError {
            switch error {
            case .userNotFound: return "No walker with that username."
            case .cannotFriendYourself: return "That's you!"
            case .alreadyFriends: return "You're already friends."
            case .requestAlreadyPending: return "A request is already pending."
            case .notConfigured: return "Friend sync isn't set up yet."
            case .notSignedIn:
                handleSessionExpired()
                return "Please sign in again."
            case .network: return "Couldn't send the request. Check your connection."
            }
        } catch {
            return "Couldn't send the request."
        }
    }

    func accept(_ request: FriendRequest) async {
        await performFriendAction { try await $0.acceptFriendRequest(id: request.id) }
    }

    func decline(_ request: FriendRequest) async {
        await performFriendAction { try await $0.declineFriendRequest(id: request.id) }
    }

    func removeFriend(_ id: UserID) async {
        await performFriendAction { try await $0.removeFriend(id) }
    }

    func blockFriend(_ id: UserID) async {
        await performFriendAction { try await $0.blockUser(id) }
    }

    private func performFriendAction(_ action: (FriendRepository) async throws -> Void) async {
        guard let friendRepository else { return }
        do {
            try await action(friendRepository)
        } catch FriendRepositoryError.notSignedIn {
            handleSessionExpired()
        } catch {
            friendsError = "That didn't go through. Check your connection and try again."
        }
        await refreshFriends()
    }

    /// Opens the Social tab focused on `id`.
    func showOnTrack(_ id: UserID) {
        trackFocus.focus(on: id, currentUserID: currentUserID)
        selectedTab = .friends
    }

    // MARK: Account

    /// Restores a saved session at launch.
    private func restoreSession() async {
        guard let backend, await backend.auth.isSignedIn else { return }
        await loadProfile(backend)
    }

    func signInWithApple(idToken: String, nonce: String) async {
        guard let backend else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await backend.auth.signInWithApple(idToken: idToken, nonce: nonce)
        } catch {
            accountError = "Couldn't sign in. Check your connection and try again."
            return
        }
        await loadProfile(backend)
        // Carry the walker chosen before signing in over to the account.
        if case .signedIn(let profile) = account, profile.avatarID != settings.avatarID {
            await pushProfile { try await backend.profiles.update(avatarID: self.settings.avatarID) }
        }
        await refreshAll()
    }

    private func loadProfile(_ backend: WalkscapeBackend) async {
        do {
            let profile = try await backend.profiles.myProfile()
            apply(profile)
        } catch BackendError.notSignedIn {
            handleSessionExpired()
        } catch {
            // Offline at launch: stay signed in with the last known name and retry later.
            if account == .signedOut {
                account = .signedIn(RemoteProfile(id: currentUserID, username: settings.username,
                                                  avatarID: settings.avatarID,
                                                  shareProgress: settings.shareProgressWithFriends))
            }
        }
    }

    private func apply(_ profile: RemoteProfile) {
        account = .signedIn(profile)
        settings.username = profile.username
        settings.shareProgressWithFriends = profile.shareProgress
        Task { await registerPushToken() }
        Task { await syncCloudSave(force: true) }
        Task { await publishShowcase() }
    }

    /// Changes the username. Returns an error message, or nil on success.
    func updateUsername(_ raw: String) async -> String? {
        guard let backend, isSignedIn else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Enter a name." }
            settings.username = String(trimmed.prefix(20))
            return nil
        }
        do {
            apply(try await backend.profiles.update(username: raw))
            return nil
        } catch ProfileUpdateError.invalidUsername {
            return "Use 3–20 lowercase letters, numbers or underscores."
        } catch ProfileUpdateError.usernameTaken {
            return "That username is taken."
        } catch {
            return "Couldn't save your username. Check your connection."
        }
    }

    func setAvatar(_ avatarID: String) {
        settings.avatarID = avatarID
        guard let backend, isSignedIn else { return }
        Task { await pushProfile { try await backend.profiles.update(avatarID: avatarID) } }
    }

    func setShareProgress(_ share: Bool) {
        settings.shareProgressWithFriends = share
        guard let backend, isSignedIn else { return }
        Task {
            await pushProfile { try await backend.profiles.update(shareProgress: share) }
            if share, let progress = todayProgress { await uploadProgress(progress, source: dataSource) }
        }
    }

    private func pushProfile(_ update: () async throws -> RemoteProfile) async {
        do {
            apply(try await update())
        } catch ProfileUpdateError.backend(.notSignedIn) {
            handleSessionExpired()
        } catch {
            accountError = "Couldn't save your profile. It will be kept on this device."
        }
    }

    /// Shares today's totals with friends. Demo data is never uploaded, and
    /// nothing is uploaded while sharing is off.
    private func uploadProgress(_ progress: DailyProgress, source: WalkingDataSourceKind) async {
        guard let backend, isSignedIn, source == .appleHealth, settings.shareProgressWithFriends else { return }
        do {
            try await backend.progressSync.sync(progress)
        } catch BackendError.notSignedIn {
            handleSessionExpired()
        } catch {
            // Offline: the next refresh retries, since nothing was recorded as uploaded.
        }
    }

    func signOut() async {
        guard let backend else { return }
        if let token = notifications.deviceToken { try? await backend.push.unregister(token: token) }
        await backend.signOut()
        account = .signedOut
        trackFocus.backToMe()
        await refreshFriends()
        await refreshTeam()
        await refreshGroups()
        await refreshReferrals()
    }

    /// Deletes the account and all server data. Returns an error message, or nil on success.
    func deleteAccount() async -> String? {
        guard let backend else { return nil }
        do {
            try await backend.deleteAccount()
        } catch {
            return "Couldn't delete your account. Check your connection and try again."
        }
        // The cloud save is gone; progress on this phone can go to the next account.
        store.cloudSaveOwner = nil
        account = .signedOut
        trackFocus.backToMe()
        await refreshFriends()
        await refreshTeam()
        await refreshGroups()
        await refreshReferrals()
        return nil
    }

    private func handleSessionExpired() {
        guard isSignedIn else { return }
        account = .signedOut
        friends = []
        friendRequests = FriendRequests()
        team = nil
        teamInvites = []
        groups = []
        referral = nil
        accountError = "You've been signed out. Sign in again to see your friends."
    }
}
