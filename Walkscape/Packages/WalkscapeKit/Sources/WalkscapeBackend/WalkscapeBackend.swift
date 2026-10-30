import Foundation
import WalkscapeDomain

/// Everything the app needs from Supabase, built from one config.
public final class WalkscapeBackend: Sendable {
    public let config: SupabaseConfig
    public let auth: SupabaseAuth
    public let api: SupabaseAPI
    public let friends: SupabaseFriendRepository
    public let profiles: ProfileService
    public let progressSync: DailyProgressSyncer
    public let teams: SupabaseTeamRepository
    public let referrals: SupabaseReferralRepository
    public let push: PushRegistry
    public let cloudSave: CloudSaveService

    public init(config: SupabaseConfig, transport: HTTPTransport = URLSessionTransport(), sessionStore: SessionStore,
                catalog: ZoneCatalog = .standard) {
        self.config = config
        let auth = SupabaseAuth(config: config, transport: transport, store: sessionStore)
        self.auth = auth
        api = SupabaseAPI(config: config, transport: transport, auth: auth)
        friends = SupabaseFriendRepository(api: api, catalog: catalog)
        profiles = ProfileService(api: api)
        progressSync = DailyProgressSyncer(api: api)
        teams = SupabaseTeamRepository(api: api) { await auth.currentSession?.userID }
        referrals = SupabaseReferralRepository(api: api)
        push = PushRegistry(api: api)
        cloudSave = CloudSaveService(api: api)
    }

    /// Permanently deletes the account and everything stored for it, then signs out locally.
    public func deleteAccount() async throws {
        try await api.call("delete_account")
        await auth.clearSession()
        await progressSync.reset()
    }

    public func signOut() async {
        await auth.signOut()
        await progressSync.reset()
    }
}
