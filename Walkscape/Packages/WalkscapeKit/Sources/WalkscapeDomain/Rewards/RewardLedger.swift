import Foundation

/// Something the game grants once: a quest, an event, a level-up, a
/// collection milestone. `id` is stable per occurrence (it includes the day
/// or week where it can recur), which is what makes claiming idempotent.
public struct Reward: Identifiable, Hashable, Sendable {
    public let id: String
    public let coins: Int
    public let xp: Int
    /// Shop items given for free (exclusive cosmetics). Already-owned items are skipped.
    public let itemIDs: [String]

    public init(id: String, coins: Int = 0, xp: Int = 0, itemIDs: [String] = []) {
        self.id = id
        self.coins = max(0, coins)
        self.xp = max(0, xp)
        self.itemIDs = itemIDs
    }
}

/// Every reward ever granted, by id. Claiming the same id again does nothing,
/// so refreshes, relaunches, repeated days and restored saves can never pay twice.
public struct RewardLedger: Codable, Hashable, Sendable {
    /// Claimed reward ids with the XP each one gave.
    public private(set) var claimed: [String: Int]
    /// Highest Explorer Level already celebrated and paid.
    public private(set) var celebratedLevel: Int

    public init() {
        claimed = [:]
        celebratedLevel = 1
    }

    enum CodingKeys: String, CodingKey { case claimed, celebratedLevel }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claimed = try container.decodeIfPresent([String: Int].self, forKey: .claimed) ?? [:]
        celebratedLevel = try container.decodeIfPresent(Int.self, forKey: .celebratedLevel) ?? 1
    }

    public func hasClaimed(_ id: String) -> Bool { claimed[id] != nil }

    /// XP from claimed rewards (quests, events…). Walking and discovery XP is
    /// derived from progression instead; see `ExplorerXP`.
    public var rewardXP: Int { claimed.values.reduce(0, +) }

    /// Grants `reward` into `wallet` unless it was already claimed. Returns whether it was granted.
    @discardableResult
    public mutating func claim(_ reward: Reward, into wallet: inout WalletState) -> Bool {
        guard claimed[reward.id] == nil else { return false }
        claimed[reward.id] = reward.xp
        wallet.receiveReward(id: reward.id, coins: reward.coins, itemIDs: reward.itemIDs)
        return true
    }

    /// Levels reached since the last call, each paid once (`ExplorerRules.coinsPerLevel`).
    public mutating func levelUps(totalXP: Int, into wallet: inout WalletState,
                                  rules: ExplorerRules = .standard) -> [Int] {
        let level = ExplorerLevel(totalXP: totalXP, rules: rules).level
        guard level > celebratedLevel else { return [] }
        let reached = Array((celebratedLevel + 1)...level)
        for newLevel in reached {
            // Level rewards give no XP themselves, so levelling can't feed itself.
            claim(Reward(id: "level-\(newLevel)", coins: rules.coinsPerLevel), into: &wallet)
        }
        celebratedLevel = level
        return reached
    }

    /// Combines two devices' ledgers without losing anything.
    public func merged(with other: RewardLedger) -> RewardLedger {
        var result = self
        result.claimed.merge(other.claimed) { max($0, $1) }
        result.celebratedLevel = max(celebratedLevel, other.celebratedLevel)
        return result
    }
}
