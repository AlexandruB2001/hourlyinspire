import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import WalkscapeDomain

/// A signed-in Supabase session.
public struct AuthSession: Codable, Hashable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: UserID

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: UserID) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
    }
}

/// Persists the session between launches (Keychain in the app).
public protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
}

public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    public init(_ session: AuthSession? = nil) {
        self.session = session
    }

    public func load() -> AuthSession? { lock.withLock { session } }
    public func save(_ session: AuthSession?) { lock.withLock { self.session = session } }
}

/// Supabase Auth (GoTrue) over plain HTTP: sign in with an Apple ID token,
/// refresh, sign out. Concurrent callers share a single refresh.
public actor SupabaseAuth {
    private let config: SupabaseConfig
    private let transport: HTTPTransport
    private let store: SessionStore
    private let now: @Sendable () -> Date
    private var session: AuthSession?
    private var loaded = false
    private var refreshTask: Task<AuthSession, Error>?

    /// Refresh this long before expiry.
    static let refreshMargin: TimeInterval = 60

    public init(config: SupabaseConfig, transport: HTTPTransport, store: SessionStore,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.transport = transport
        self.store = store
        self.now = now
    }

    public var currentSession: AuthSession? {
        loadIfNeeded()
        return session
    }

    public var isSignedIn: Bool { currentSession != nil }

    /// Exchanges an identity token from Sign in with Apple for a session.
    /// `nonce` is the raw (unhashed) nonce whose SHA-256 was sent to Apple.
    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        try await tokenRequest(grantType: "id_token",
                               body: ["provider": "apple", "id_token": idToken, "nonce": nonce])
    }

    /// An access token valid for at least `refreshMargin`, refreshing if needed.
    public func validAccessToken() async throws -> String {
        loadIfNeeded()
        guard let session else { throw BackendError.notSignedIn }
        if session.expiresAt.timeIntervalSince(now()) > Self.refreshMargin {
            return session.accessToken
        }
        return try await refresh().accessToken
    }

    /// Forces a refresh (e.g. after a 401). Concurrent calls share one request.
    @discardableResult
    public func refresh() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        loadIfNeeded()
        guard let refreshToken = session?.refreshToken else { throw BackendError.notSignedIn }
        let task = Task { try await self.tokenRequest(grantType: "refresh_token", body: ["refresh_token": refreshToken]) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch BackendError.server(let status, _, _) where (400..<500).contains(status) {
            // The refresh token was revoked or expired: the user must sign in again.
            setSession(nil)
            throw BackendError.notSignedIn
        }
    }

    /// Signs out locally, and on the server when reachable.
    public func signOut() async {
        loadIfNeeded()
        if let token = session?.accessToken {
            var request = URLRequest(url: config.url.appendingPathComponent("auth/v1/logout"))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await transport.send(request)
        }
        setSession(nil)
    }

    /// Forgets the session without contacting the server (e.g. after account deletion).
    public func clearSession() {
        setSession(nil)
    }

    // MARK: Private

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: String }
        let access_token: String
        let refresh_token: String
        let expires_in: Double?
        let expires_at: Double?
        let user: User
    }

    private func tokenRequest(grantType: String, body: [String: String]) async throws -> AuthSession {
        var components = URLComponents(url: config.url.appendingPathComponent("auth/v1/token"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.network(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseAPI.serverError(status: response.statusCode, data: data)
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw BackendError.decoding("Unexpected auth response")
        }
        let expiresAt = token.expires_at.map { Date(timeIntervalSince1970: $0) }
            ?? now().addingTimeInterval(token.expires_in ?? 3_600)
        let newSession = AuthSession(accessToken: token.access_token, refreshToken: token.refresh_token,
                                     expiresAt: expiresAt, userID: UserID(token.user.id.lowercased()))
        setSession(newSession)
        return newSession
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        session = store.load()
    }

    private func setSession(_ newValue: AuthSession?) {
        loaded = true
        session = newValue
        store.save(newValue)
    }
}
