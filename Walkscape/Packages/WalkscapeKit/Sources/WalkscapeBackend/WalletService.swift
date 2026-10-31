import Foundation
import WalkscapeDomain

/// Coin purchases the server makes, charges and records (see migration
/// 20261110000001): Mystery Boxes (rolled on the server) and companion
/// adoptions. Each is paid from the cloud save, so sync it first.
public struct WalletService: Sendable {
    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    /// What the server charged, under which wallet key, and the item it gave.
    public struct Purchase: Hashable, Sendable {
        public let chargeKey: String
        public let coins: Int
        public let itemID: String?
    }

    public enum PurchaseError: Error, Equatable, Sendable {
        case insufficientCoins
        case soldOut
        /// The server has no up-to-date cloud save to pay from.
        case needsCloudSave
        case notSignedIn
        case network(String)
    }

    /// Buys and opens a Mystery Box. Retrying with the same `requestID` returns
    /// the same prize and charges once.
    public func openMysteryBox(requestID: UUID, day: LocalDay) async throws -> Purchase {
        struct Params: Encodable {
            let p_request_id: String
            let p_day: String
        }
        struct Row: Decodable {
            let item_id: String
            let charge_key: String
            let coins: Int
        }
        let rows: [Row] = try await run {
            try await api.call("open_mystery_box", Params(p_request_id: requestID.uuidString.lowercased(), p_day: day.isoString))
        }
        guard let row = rows.first else { throw PurchaseError.network("Unexpected response from the server") }
        return Purchase(chargeKey: row.charge_key, coins: row.coins, itemID: row.item_id)
    }

    /// Adopts a companion species (charged once per species, ever).
    public func adoptCompanion(speciesID: String) async throws -> Purchase {
        struct Params: Encodable { let p_species: String }
        struct Row: Decodable {
            let charge_key: String
            let coins: Int
        }
        let rows: [Row] = try await run { try await api.call("adopt_companion", Params(p_species: speciesID)) }
        guard let row = rows.first else { throw PurchaseError.network("Unexpected response from the server") }
        return Purchase(chargeKey: row.charge_key, coins: row.coins, itemID: nil)
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as BackendError {
            throw Self.map(error)
        }
    }

    static func map(_ error: BackendError) -> PurchaseError {
        switch error {
        case .notSignedIn: return .notSignedIn
        case .network(let message): return .network(message)
        case .server(_, _, let message):
            switch message {
            case "insufficient_coins": return .insufficientCoins
            case "sold_out": return .soldOut
            case "no_cloud_save", "update_app": return .needsCloudSave
            case "not_authenticated": return .notSignedIn
            default: return .network(message)
            }
        case .invalidResponse, .decoding: return .network("Unexpected response from the server")
        }
    }
}
