import Foundation
import WalkscapeDomain

/// Reads and writes the player's `CloudSave` (see migration 20261031000001).
public struct CloudSaveService: Sendable {
    public struct Stored: Sendable {
        public let save: CloudSave
        public let version: Int
    }

    public enum SaveError: Error, Equatable, Sendable {
        /// Another phone saved first. Fetch, merge and try again.
        case conflict
        /// The save is from a newer app version; leave it alone.
        case newerSchema
    }

    private let api: SupabaseAPI

    public init(api: SupabaseAPI) {
        self.api = api
    }

    /// Reads the schema first, so a save written by a newer app version is
    /// reported instead of half-decoded.
    struct Row: Decodable {
        struct Header: Decodable { let schema: Int }
        enum CodingKeys: String, CodingKey { case save, version }

        let version: Int
        let save: CloudSave?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            let header = try container.decode(Header.self, forKey: .save)
            if header.schema <= CloudSave.currentSchema {
                save = try container.decode(CloudSave.self, forKey: .save)
            } else {
                save = nil
            }
        }
    }

    /// The stored save, or nil if this account has none yet.
    public func fetch() async throws -> Stored? {
        let rows: [Row] = try await api.call("get_player_save")
        guard let row = rows.first else { return nil }
        guard let save = row.save else { throw SaveError.newerSchema }
        return Stored(save: save, version: row.version)
    }

    /// Writes `save` over version `baseVersion` (0 for the first save). Returns the new version.
    public func store(_ save: CloudSave, baseVersion: Int) async throws -> Int {
        struct Params: Encodable { let p_save: CloudSave; let p_base_version: Int }
        do {
            return try await api.call("put_player_save", Params(p_save: save, p_base_version: baseVersion))
        } catch let error as BackendError where error.serverMessage == "save_conflict" {
            throw SaveError.conflict
        }
    }

    /// Fetches, merges with `local` and stores, retrying once if another
    /// phone saved in between. Returns the merged save now stored.
    public func sync(_ local: CloudSave) async throws -> CloudSave {
        for attempt in 0..<3 {
            let remote = try await fetch()
            let merged = remote.map { local.merged(with: $0.save) } ?? local
            do {
                _ = try await store(merged, baseVersion: remote?.version ?? 0)
                return merged
            } catch SaveError.conflict where attempt < 2 {
                continue
            }
        }
        throw SaveError.conflict
    }
}
