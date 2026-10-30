import Foundation
import WalkscapeDomain

/// Records App Store purchases on the server (after Apple's signature is
/// checked there) and reads back what the account owns. See migration
/// 20261105000001 and the verify-purchase Edge Function.
public struct PurchaseService: Sendable {
    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    /// Sends a StoreKit 2 transaction's signed JWS for verification.
    public func verify(signedTransaction: String) async throws {
        struct Body: Encodable { let signedTransaction: String }
        _ = try await api.invokeFunction("verify-purchase", Body(signedTransaction: signedTransaction))
    }

    /// What the account owns according to the server.
    public func entitlements() async throws -> Entitlements {
        struct Row: Decodable {
            let product_id: String
            let expires_at: Date?
        }
        let rows: [Row] = try await api.call("my_entitlements")
        var result = Entitlements()
        for row in rows {
            guard let product = StoreCatalog.product(withID: row.product_id) else { continue }
            switch product.kind {
            case .bundle: result.bundles.insert(product.id)
            case .subscription:
                if let expires = row.expires_at { result.plusExpires = max(result.plusExpires ?? expires, expires) }
            }
        }
        return result
    }
}
