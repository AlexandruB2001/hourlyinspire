import Foundation

/// Stores this device's push token on the server so friend requests and
/// team invites can reach it with the app closed (see supabase/functions/send-push).
public struct PushRegistry: Sendable {
    public enum Environment: String, Sendable {
        /// Debug builds installed from Xcode.
        case sandbox
        /// TestFlight and App Store builds.
        case production
    }

    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    /// APNs hands the token over as bytes; the server stores it as hex.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    public func register(token: String, environment: Environment, social: Bool) async throws {
        struct Params: Encodable { let p_token: String; let p_environment: String; let p_social: Bool }
        try await api.call("register_push_token", Params(p_token: token, p_environment: environment.rawValue, p_social: social))
    }

    public func unregister(token: String) async throws {
        struct Params: Encodable { let p_token: String }
        try await api.call("unregister_push_token", Params(p_token: token))
    }
}
