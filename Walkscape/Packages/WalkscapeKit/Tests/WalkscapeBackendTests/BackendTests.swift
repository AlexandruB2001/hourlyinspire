import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import WalkscapeBackend
import WalkscapeDomain

/// Records requests and replies with queued responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        let status: Int
        let body: String
    }

    private let lock = NSLock()
    private var replies: [Reply] = []
    private(set) var requests: [URLRequest] = []

    func enqueue(_ status: Int, _ body: String) {
        lock.withLock { replies.append(Reply(status: status, body: body)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = try lock.withLock {
            requests.append(request)
            guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
            return replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }

    var requestCount: Int { lock.withLock { requests.count } }

    func body(_ index: Int) -> [String: Any] {
        let data = lock.withLock { requests[index].httpBody } ?? Data()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func path(_ index: Int) -> String {
        lock.withLock { requests[index].url!.path }
    }
}

final class BackendTests: XCTestCase {
    let config = SupabaseConfig(url: URL(string: "https://demo.supabase.co")!, anonKey: "anon-key")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func tokenJSON(access: String, refresh: String, expiresIn: Int = 3_600, user: String = "0A0B-USER") -> String {
        """
        {"access_token":"\(access)","refresh_token":"\(refresh)","expires_in":\(expiresIn),"token_type":"bearer","user":{"id":"\(user)"}}
        """
    }

    func makeBackend(session: AuthSession? = nil, transport: MockTransport) -> (SupabaseAuth, SupabaseAPI) {
        let fixedNow = now
        let auth = SupabaseAuth(config: config, transport: transport, store: InMemorySessionStore(session), now: { fixedNow })
        return (auth, SupabaseAPI(config: config, transport: transport, auth: auth))
    }

    func validSession() -> AuthSession {
        AuthSession(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(3_000), userID: "me")
    }

    // MARK: Config

    func testConfigFromBuildSettings() {
        XCTAssertEqual(SupabaseConfig(host: "abc.supabase.co", anonKey: "key")?.url.absoluteString, "https://abc.supabase.co")
        XCTAssertEqual(SupabaseConfig(host: "127.0.0.1:54321", scheme: "http", anonKey: "key")?.url.absoluteString,
                       "http://127.0.0.1:54321")
        XCTAssertNil(SupabaseConfig(host: "", anonKey: "key"), "missing host means not configured")
        XCTAssertNil(SupabaseConfig(host: "abc.supabase.co", anonKey: nil))
        XCTAssertNil(SupabaseConfig(host: "$(SUPABASE_HOST)", anonKey: "key"), "unexpanded build settings are ignored")
    }

    // MARK: Auth

    func testSignInWithAppleStoresSession() async throws {
        let transport = MockTransport()
        transport.enqueue(200, tokenJSON(access: "a", refresh: "r"))
        let (auth, _) = makeBackend(transport: transport)

        let session = try await auth.signInWithApple(idToken: "apple-jwt", nonce: "raw-nonce")
        XCTAssertEqual(session.userID, "0a0b-user")
        XCTAssertEqual(session.expiresAt, now.addingTimeInterval(3_600))
        let isSignedIn = await auth.isSignedIn
        XCTAssertTrue(isSignedIn)

        let request = transport.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://demo.supabase.co/auth/v1/token?grant_type=id_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(transport.body(0)["provider"] as? String, "apple")
        XCTAssertEqual(transport.body(0)["id_token"] as? String, "apple-jwt")
        XCTAssertEqual(transport.body(0)["nonce"] as? String, "raw-nonce")
    }

    func testExpiringTokenIsRefreshedBeforeUse() async throws {
        let transport = MockTransport()
        transport.enqueue(200, tokenJSON(access: "access-2", refresh: "refresh-2"))
        transport.enqueue(200, "[]")
        var session = validSession()
        session.expiresAt = now.addingTimeInterval(30)
        let (_, api) = makeBackend(session: session, transport: transport)

        let _: [FriendSummaryRow] = try await api.call("friend_daily_summaries")
        XCTAssertEqual(transport.requests[0].url?.query, "grant_type=refresh_token")
        XCTAssertEqual(transport.body(0)["refresh_token"] as? String, "refresh-1")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testUnauthorizedResponseRefreshesOnceAndRetries() async throws {
        let transport = MockTransport()
        transport.enqueue(401, #"{"message":"JWT expired"}"#)
        transport.enqueue(200, tokenJSON(access: "access-2", refresh: "refresh-2"))
        transport.enqueue(200, "[]")
        let (_, api) = makeBackend(session: validSession(), transport: transport)

        let _: [FriendSummaryRow] = try await api.call("friend_daily_summaries")
        XCTAssertEqual(transport.requestCount, 3)
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testRevokedRefreshTokenSignsOut() async throws {
        let transport = MockTransport()
        transport.enqueue(400, #"{"error":"invalid_grant","error_description":"Refresh Token Not Found"}"#)
        var session = validSession()
        session.expiresAt = now
        let (auth, api) = makeBackend(session: session, transport: transport)

        do {
            try await api.call("delete_account")
            XCTFail("expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? BackendError, .notSignedIn)
        }
        let isSignedIn = await auth.isSignedIn
        XCTAssertFalse(isSignedIn)
    }

    func testCallsWithoutSessionFailFast() async {
        let transport = MockTransport()
        let (_, api) = makeBackend(transport: transport)
        do {
            try await api.call("delete_account")
            XCTFail("expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? BackendError, .notSignedIn)
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testSignOutClearsSessionEvenOffline() async {
        let transport = MockTransport()
        let (auth, _) = makeBackend(session: validSession(), transport: transport)
        await auth.signOut()
        XCTAssertEqual(transport.path(0), "/auth/v1/logout")
        let isSignedIn = await auth.isSignedIn
        XCTAssertFalse(isSignedIn)
    }

    // MARK: Cloud save

    func saveJSON(coins: Int, schema: Int = 1) throws -> String {
        var wallet = WalletState(rules: CoinRules(starterCoins: coins))
        _ = wallet.openChest()
        let save = CloudSave(progression: ProgressionState(), wallet: wallet, journal: JourneyJournal(),
                             ledger: RewardLedger(), companion: nil, savedAt: now)
        var object = try JSONSerialization.jsonObject(with: SupabaseAPI.encoder.encode(save)) as! [String: Any]
        object["schema"] = schema
        return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    func testCloudSyncMergesAndRetriesAfterAConflict() async throws {
        let transport = MockTransport()
        transport.enqueue(200, "[{\"version\":3,\"save\":\(try saveJSON(coins: 500))}]")
        transport.enqueue(400, #"{"code":"40001","message":"save_conflict"}"#)
        transport.enqueue(200, "[{\"version\":4,\"save\":\(try saveJSON(coins: 700))}]")
        transport.enqueue(200, "5")
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let local = CloudSave(progression: ProgressionState(), wallet: WalletState(rules: CoinRules(starterCoins: 50)),
                              journal: JourneyJournal(), ledger: RewardLedger(), companion: nil, savedAt: now)

        let merged = try await CloudSaveService(api: api).sync(local)

        XCTAssertEqual(merged.wallet.coins, 700, "the newer remote earnings win")
        XCTAssertEqual(transport.path(1), "/rest/v1/rpc/put_player_save")
        XCTAssertEqual(transport.body(1)["p_base_version"] as? Int, 3)
        XCTAssertEqual(transport.body(3)["p_base_version"] as? Int, 4)
        XCTAssertEqual(transport.requestCount, 4)
    }

    func testCloudSaveFromANewerAppIsLeftAlone() async throws {
        let transport = MockTransport()
        transport.enqueue(200, "[{\"version\":1,\"save\":{\"schema\":99}}]")
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        do {
            _ = try await CloudSaveService(api: api).fetch()
            XCTFail("expected newerSchema")
        } catch CloudSaveService.SaveError.newerSchema {}
    }

    // MARK: Push

    func testPushTokenIsRegisteredAsHex() async throws {
        XCTAssertEqual(PushRegistry.hex(Data([0x0a, 0xff, 0x10])), "0aff10")
        let transport = MockTransport()
        transport.enqueue(204, "")
        transport.enqueue(204, "")
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let registry = PushRegistry(api: api)
        try await registry.register(token: "abcd", environment: .production, social: false)
        XCTAssertEqual(transport.path(0), "/rest/v1/rpc/register_push_token")
        XCTAssertEqual(transport.body(0)["p_token"] as? String, "abcd")
        XCTAssertEqual(transport.body(0)["p_environment"] as? String, "production")
        XCTAssertEqual(transport.body(0)["p_social"] as? Bool, false)
        try await registry.unregister(token: "abcd")
        XCTAssertEqual(transport.path(1), "/rest/v1/rpc/unregister_push_token")
    }

    // MARK: Friends

    func testFriendSummariesMapping() async throws {
        let transport = MockTransport()
        transport.enqueue(200, """
        [
          {"user_id":"AAAA","username":"taylor","avatar_id":"plum","local_date":"2026-10-25","steps":9480,
           "distance_meters":7200,"distance_source":"recorded","updated_at":"\(PostgresDate.format(now.addingTimeInterval(-600)))"},
          {"user_id":"bbbb","username":"sam","avatar_id":"sunny","local_date":"2026-10-25","steps":610,
           "distance_meters":400,"distance_source":"recorded","updated_at":"\(PostgresDate.format(now.addingTimeInterval(-5 * 3600)))"},
          {"user_id":"cccc","username":"riley","avatar_id":"fern","local_date":null,"steps":null,
           "distance_meters":null,"distance_source":null,"updated_at":null}
        ]
        """)
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let repository = SupabaseFriendRepository(api: api)
        let summaries = try await repository.friendSummaries(for: LocalDay(year: 2026, month: 10, day: 25), now: now)

        XCTAssertEqual(transport.path(0), "/rest/v1/rpc/friend_daily_summaries")
        XCTAssertEqual(transport.body(0)["p_local_date"] as? String, "2026-10-25")
        XCTAssertEqual(summaries.map(\.username), ["taylor", "sam", "riley"])
        XCTAssertEqual(summaries[0].userID, "aaaa")
        XCTAssertEqual(summaries[0].dailyDistanceMeters, 7_200)
        XCTAssertEqual(summaries[0].currentZoneID, "snowy-ridge")
        XCTAssertEqual(summaries[0].progressAvailability, .current)
        XCTAssertEqual(summaries[1].progressAvailability, .stale)
        XCTAssertEqual(summaries[2].progressAvailability, .unavailable)
        XCTAssertNil(summaries[2].dailyDistanceMeters)
    }

    func testFriendRequestErrorsAreMapped() async {
        let cases: [(String, FriendRepositoryError)] = [
            ("user_not_found", .userNotFound), ("cannot_friend_self", .cannotFriendYourself),
            ("already_friends", .alreadyFriends), ("request_already_pending", .requestAlreadyPending),
        ]
        for (message, expected) in cases {
            let transport = MockTransport()
            transport.enqueue(400, #"{"code":"P0002","details":null,"hint":null,"message":"\#(message)"}"#)
            let (_, api) = makeBackend(session: validSession(), transport: transport)
            do {
                try await SupabaseFriendRepository(api: api).sendFriendRequest(toUsername: "alex")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? FriendRepositoryError, expected)
            }
        }
    }

    func testPendingRequestsAreSplitByDirection() async throws {
        let transport = MockTransport()
        transport.enqueue(200, """
        [{"id":"R1","user_id":"U1","username":"casey","avatar_id":"sunny","direction":"incoming","created_at":"2026-10-25T09:00:00.123456+00:00"},
         {"id":"R2","user_id":"U2","username":"jordan","avatar_id":"frost","direction":"outgoing","created_at":"2026-10-24T09:00:00+00:00"}]
        """)
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let requests = try await SupabaseFriendRepository(api: api).friendRequests()
        XCTAssertEqual(requests.incoming.map(\.username), ["casey"])
        XCTAssertEqual(requests.outgoing.map(\.username), ["jordan"])
        XCTAssertEqual(requests.incoming[0].id, "r1")
    }

    func testVoidFunctionsAcceptEmptyResponses() async throws {
        let transport = MockTransport()
        transport.enqueue(204, "")
        transport.enqueue(200, "null")
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let repository = SupabaseFriendRepository(api: api)
        try await repository.removeFriend("u1")
        try await repository.blockUser("u2")
        XCTAssertEqual(transport.body(0)["p_friend_id"] as? String, "u1")
        XCTAssertEqual(transport.path(1), "/rest/v1/rpc/block_user")
    }

    func testOfflineIsANetworkError() async {
        let transport = MockTransport()
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        do {
            _ = try await SupabaseFriendRepository(api: api).friendRequests()
            XCTFail("expected an error")
        } catch {
            guard case .network = error as? FriendRepositoryError else { return XCTFail("got \(error)") }
        }
    }

    // MARK: Progress sync

    func testDuplicateSyncsAreSkipped() async throws {
        let transport = MockTransport()
        let row = #"{"user_id":"me","local_date":"2026-10-25"}"#
        transport.enqueue(200, row)
        transport.enqueue(200, row)
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let syncer = DailyProgressSyncer(api: api)
        let day = LocalDay(year: 2026, month: 10, day: 25)
        func progress(_ meters: Int, at offset: TimeInterval) -> DailyProgress {
            DailyProgress(userID: "me", localDate: day, timeZoneIdentifier: "Europe/London", steps: meters,
                          distanceMeters: meters, distanceSource: .recorded, updatedAt: now.addingTimeInterval(offset))
        }

        let first = try await syncer.sync(progress(2_400, at: 0))
        let repeated = try await syncer.sync(progress(2_400, at: 60))
        let changed = try await syncer.sync(progress(2_500, at: 120))
        XCTAssertEqual([first, repeated, changed], [.uploaded, .skippedUnchanged, .uploaded])
        XCTAssertEqual(transport.requestCount, 2)

        let body = transport.body(0)
        XCTAssertEqual(transport.path(0), "/rest/v1/rpc/upsert_daily_progress")
        XCTAssertEqual(body["p_local_date"] as? String, "2026-10-25")
        XCTAssertEqual(body["p_distance_meters"] as? Int, 2_400)
        XCTAssertEqual(body["p_distance_source"] as? String, "recorded")
        XCTAssertEqual(body["p_time_zone"] as? String, "Europe/London")
        XCTAssertNotNil(PostgresDate.parse(body["p_client_updated_at"] as? String ?? ""))
    }

    func testFailedSyncIsRetriedNextTime() async throws {
        let transport = MockTransport()
        transport.enqueue(500, #"{"message":"boom"}"#)
        transport.enqueue(200, "{}")
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let syncer = DailyProgressSyncer(api: api)
        let progress = DailyProgress(userID: "me", localDate: LocalDay(year: 2026, month: 10, day: 25),
                                     timeZoneIdentifier: "UTC", steps: 1, distanceMeters: 1, distanceSource: .recorded,
                                     updatedAt: now)
        do { _ = try await syncer.sync(progress); XCTFail("expected failure") } catch {}
        let retry = try await syncer.sync(progress)
        XCTAssertEqual(retry, .uploaded)
    }

    func testUnavailableProgressIsNeverUploaded() async throws {
        let transport = MockTransport()
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let progress = DailyProgress(userID: "me", localDate: LocalDay(year: 2026, month: 10, day: 25),
                                     timeZoneIdentifier: "UTC", steps: 0, distanceMeters: 0, distanceSource: .unavailable,
                                     updatedAt: now)
        let outcome = try await DailyProgressSyncer(api: api).sync(progress)
        XCTAssertEqual(outcome, .skippedUnavailable)
        XCTAssertEqual(transport.requestCount, 0)
    }

    // MARK: Profiles

    func testProfileUpdateValidatesAndMapsErrors() async throws {
        XCTAssertEqual(ProfileService.normalizedUsername("  Alex_W "), "alex_w")
        XCTAssertNil(ProfileService.normalizedUsername("al"))
        XCTAssertNil(ProfileService.normalizedUsername("no spaces"))

        let transport = MockTransport()
        transport.enqueue(409, #"{"code":"23505","message":"username_taken"}"#)
        transport.enqueue(200, #"{"id":"ME","username":"alex","avatar_id":"sky","share_progress":false,"created_at":"x"}"#)
        let (_, api) = makeBackend(session: validSession(), transport: transport)
        let service = ProfileService(api: api)

        do {
            _ = try await service.update(username: "bob")
            XCTFail("expected usernameTaken")
        } catch {
            XCTAssertEqual(error as? ProfileUpdateError, .usernameTaken)
        }
        do {
            _ = try await service.update(username: "x")
            XCTFail("expected invalidUsername")
        } catch {
            XCTAssertEqual(error as? ProfileUpdateError, .invalidUsername)
        }

        let profile = try await service.update(avatarID: "sky", shareProgress: false)
        XCTAssertEqual(profile, RemoteProfile(id: "me", username: "alex", avatarID: "sky", shareProgress: false))
        // Only provided fields are sent, so the others keep their values.
        XCTAssertEqual(Set(transport.body(1).keys), ["p_avatar_id", "p_share_progress"])
    }

    // MARK: Dates

    func testPostgresTimestampParsing() {
        let reference = Date(timeIntervalSince1970: 1_761_400_531.123)
        XCTAssertEqual(PostgresDate.parse("2025-10-25T13:55:31.123456+00:00")!.timeIntervalSince1970,
                       reference.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(PostgresDate.parse("2025-10-25 13:55:31.1+00")!.timeIntervalSince1970,
                       1_761_400_531.1, accuracy: 0.001)
        XCTAssertNotNil(PostgresDate.parse("2025-10-25T13:55:31Z"))
        XCTAssertNil(PostgresDate.parse("yesterday"))
    }
}
