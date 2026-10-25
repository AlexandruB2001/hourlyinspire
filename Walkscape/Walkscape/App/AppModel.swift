import Foundation
import Observation
import WalkscapeBackend
import WalkscapeDomain

/// App-wide state. Views read from it; all data flows in through `refresh*`.
/// Game logic lives in WalkscapeDomain — this type only coordinates.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case journey, friends, world, profile }

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
        await backend.signOut()
        account = .signedOut
        trackFocus.backToMe()
        await refreshFriends()
    }

    /// Deletes the account and all server data. Returns an error message, or nil on success.
    func deleteAccount() async -> String? {
        guard let backend else { return nil }
        do {
            try await backend.deleteAccount()
        } catch {
            return "Couldn't delete your account. Check your connection and try again."
        }
        account = .signedOut
        trackFocus.backToMe()
        await refreshFriends()
        return nil
    }

    private func handleSessionExpired() {
        guard isSignedIn else { return }
        account = .signedOut
        friends = []
        friendRequests = FriendRequests()
        accountError = "You've been signed out. Sign in again to see your friends."
    }
}
