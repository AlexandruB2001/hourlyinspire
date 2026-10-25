import Foundation
import Security
import WalkscapeBackend

/// Keeps the Supabase session in the Keychain, available after first unlock
/// so background HealthKit deliveries can still sync.
final class KeychainSessionStore: SessionStore, @unchecked Sendable {
    private let service = "com.walkscape.supabase-session"
    private let account = "default"

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

extension SupabaseConfig {
    /// Reads the connection from Info.plist (filled from Config/*.xcconfig).
    static var fromBundle: SupabaseConfig? {
        let info = Bundle.main.infoDictionary ?? [:]
        return SupabaseConfig(host: info["SupabaseHost"] as? String,
                              scheme: info["SupabaseScheme"] as? String,
                              anonKey: info["SupabaseAnonKey"] as? String)
    }
}
