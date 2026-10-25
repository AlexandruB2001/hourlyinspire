import Foundation
import Observation
import WalkscapeDomain

/// App-wide state. Views read from it; all data flows in through `refresh*`.
/// Game logic lives in WalkscapeDomain — this type only coordinates.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case journey, friends, world, profile }

    // MARK: Dependencies

    let engine = ZoneProgressionEngine()
    let demoProvider = MockWalkingDataProvider()
    private let healthProvider = HealthKitWalkingDataProvider()
    private let friendRepository: FriendRepository
    private let store: LocalStore
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    @ObservationIgnored private var lastAutoRefresh = Date.distantPast

    // MARK: State

    var selectedTab: Tab = .journey
    var settings: AppSettings {
        didSet { store.save(settings) }
    }
    private(set) var sync = WalkingSyncStatus()
    private(set) var progression: ProgressionState
    private(set) var authorization: WalkingAuthorizationState = .notDetermined
    private(set) var friends: [FriendSummary] = []
    private(set) var friendRequests = FriendRequests()
    private(set) var friendsError: String?
    private(set) var isLoadingFriends = false
    /// Set when a refresh crosses one or more zone boundaries; cleared by the UI.
    var celebration: ZoneCelebration?
    /// The shared track's focus. Lives here so other screens can deep-link to a friend.
    var trackFocus = TrackFocusController()
    /// Ticks every 30 s so relative times and staleness stay current.
    private(set) var now = Date()

    /// Local-only identity until Supabase auth lands (Milestone 4).
    let currentUserID: UserID = "me"
    var timeZone: TimeZone { .current }

    init(store: LocalStore = LocalStore(), friendRepository: FriendRepository = MockFriendRepository()) {
        self.store = store
        self.friendRepository = friendRepository
        let settings = store.loadSettings()
        self.settings = settings
        let source = settings.dataSource ?? Self.defaultSource
        progression = store.loadProgression(source)
        if let saved = store.loadLastProgress(source) { sync.restore(saved) }
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
            await refreshAll()
            startHealthObservationIfPossible()
        }
    }

    /// Call when the app becomes active.
    func didBecomeActive() {
        Task { await refreshAll() }
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
        async let walking: Void = refreshWalking()
        async let social: Void = refreshFriends()
        _ = await (walking, social)
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
            if let newCelebration = event.celebration { celebration = newCelebration }
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
        if let saved = store.loadLastProgress(source) { sync.restore(saved) }
        celebration = nil
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
        sync = WalkingSyncStatus()
        Task { await refreshWalking() }
    }

    // MARK: Friends

    func refreshFriends() async {
        isLoadingFriends = true
        defer { isLoadingFriends = false }
        do {
            async let summaries = friendRepository.friendSummaries(for: today, now: Date())
            async let requests = friendRepository.friendRequests()
            (friends, friendRequests) = try await (summaries, requests)
            friendsError = nil
            trackFocus.reconcile(with: trackParticipants)
        } catch {
            friendsError = "Couldn't reach your friends right now. Showing the last update."
        }
    }

    /// Returns a user-facing error message, or nil on success.
    func sendFriendRequest(to username: String) async -> String? {
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
            case .network: return "Couldn't send the request. Check your connection."
            }
        } catch {
            return "Couldn't send the request."
        }
    }

    func accept(_ request: FriendRequest) async {
        try? await friendRepository.acceptFriendRequest(id: request.id)
        await refreshFriends()
    }

    func decline(_ request: FriendRequest) async {
        try? await friendRepository.declineFriendRequest(id: request.id)
        await refreshFriends()
    }

    func removeFriend(_ id: UserID) async {
        try? await friendRepository.removeFriend(id)
        await refreshFriends()
    }

    func blockFriend(_ id: UserID) async {
        try? await friendRepository.blockUser(id)
        await refreshFriends()
    }

    /// Opens the Friends tab focused on `id`.
    func showOnTrack(_ id: UserID) {
        trackFocus.focus(on: id, currentUserID: currentUserID)
        selectedTab = .friends
    }
}
