import Foundation
import Observation
import UIKit
import WalkscapeBackend
import WalkscapeDomain

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
        notificationPreferences = store.loadNotificationPreferences(legacyReminder: settings.dailyReminderEnabled)
        notificationLedger = store.loadNotificationLedger()
        companion = Self.companion(for: source, store: store, progression: progression,
                                   today: LocalDay(date: Date(), timeZone: .current))
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
        _ = await (walking, social, team, referrals)
        await syncCloudSave()
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
            processLevelUps(source: source)
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
        companion = Self.companion(for: source, store: store, progression: progression, today: today)
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
        store.save(nil, for: .demo)
        companion = Self.companion(for: .demo, store: store, progression: progression, today: today)
        sync = WalkingSyncStatus()
        Task { await refreshWalking() }
    }

    // MARK: Companion & journal

    var needsCompanionChoice: Bool { companion == nil }

    var companionGrowth: CompanionGrowth? { companion?.growth(lifetimeMeters: progression.lifetimeMeters) }

    func chooseCompanion(_ species: CompanionSpecies) {
        store.companionSpeciesID = species.id
        let adopted = CompanionState(speciesID: species.id, adoptedOn: today, lifetimeMeters: progression.lifetimeMeters)
        companion = adopted
        store.save(adopted, for: dataSource)
        recordInJournal([JournalEvents.adoption(of: adopted)])
        startAdsIfReady()
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

    func createTeam(named name: String) async -> String? { await teamAction { try await $0.createTeam(named: name) } }
    func joinTeam(code: String) async -> String? { await teamAction { try await $0.joinTeam(code: code) } }
    func leaveTeam() async -> String? { await teamAction { try await $0.leaveTeam() } }
    func inviteToTeam(_ friend: UserID) async -> String? { await teamAction { try await $0.invite(friend: friend) } }
    func respond(to invite: TeamInvite, accept: Bool) async -> String? {
        await teamAction { try await $0.respond(to: invite, accept: accept) }
    }

    // MARK: Shop

    /// The walker's current outfit, in draw order.
    var outfit: [String] { wallet.outfit }

    /// Opens one chest found on today's walk. Returns the coins it held.
    func openChest() -> Int? {
        let coins = wallet.openChest()
        store.save(wallet, for: dataSource)
        if coins != nil {
            rollQuests()
            questTracker.recordChestOpened()
            store.save(questTracker, for: dataSource)
        }
        return coins
    }

    /// Buys `item` and puts it on straight away.
    func buy(_ item: ShopItem) -> PurchaseResult {
        let result = wallet.buy(item)
        if case .purchased = result { wallet.equip(item) }
        store.save(wallet, for: dataSource)
        return result
    }

    func openMysteryBox() -> PurchaseResult {
        let result = wallet.openMysteryBox()
        store.save(wallet, for: dataSource)
        return result
    }

    func toggleEquipped(_ item: ShopItem) {
        if wallet.isEquipped(item) { wallet.unequip(item.slot) } else { wallet.equip(item) }
        store.save(wallet, for: dataSource)
    }

    // MARK: Explorer level

    var explorerXP: ExplorerXP { ExplorerXP(progression: progression, ledger: ledger) }
    var explorerLevel: ExplorerLevel { ExplorerLevel(totalXP: explorerXP.total) }

    /// Pays and celebrates any levels reached since the last check. Safe to
    /// call after every refresh: each level is paid once (see `RewardLedger`).
    private func processLevelUps(source: WalkingDataSourceKind) {
        let levels = ledger.levelUps(totalXP: explorerXP.total, into: &wallet)
        guard let top = levels.last else { return }
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
        guard dataSource == .appleHealth else { return }
        progression = save.progression
        wallet = save.wallet
        journal = save.journal
        ledger = save.ledger
        if let restored = save.companion { companion = restored }
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
        guard await ads.presentRewardedAd(), let coins = adState.recordRewardedAd(on: today) else { return nil }
        store.save(adState)
        updateHealthWallet { $0.earnAdReward(coins) }
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

    /// Opens the Friends tab focused on `id`.
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
        referral = nil
        accountError = "You've been signed out. Sign in again to see your friends."
    }
}
