import Foundation

/// Everything personal that should follow an account to a new phone: the
/// Apple Health progression, wallet, journal, reward ledger and companion.
/// Demo-mode data is never saved to the cloud.
public struct CloudSave: Codable, Hashable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var progression: ProgressionState
    public var wallet: WalletState
    public var journal: JourneyJournal
    public var ledger: RewardLedger
    public var companion: CompanionState?
    /// Profile look. Nil in saves from before titles existed.
    public var showcase: ProfileShowcase?
    public var savedAt: Date

    public init(progression: ProgressionState, wallet: WalletState, journal: JourneyJournal, ledger: RewardLedger,
                companion: CompanionState?, showcase: ProfileShowcase? = nil, savedAt: Date) {
        schema = Self.currentSchema
        self.progression = progression
        self.wallet = wallet
        self.journal = journal
        self.ledger = ledger
        self.companion = companion
        self.showcase = showcase
        self.savedAt = savedAt
    }

    /// This device's save combined with another one. Nothing earned on either
    /// side is lost; see each type's `merged(with:)` for the rules.
    public func merged(with other: CloudSave) -> CloudSave {
        let companion: CompanionState?
        switch (self.companion, other.companion) {
        case let (mine?, theirs?): companion = mine.merged(with: theirs)
        case let (mine, theirs): companion = mine ?? theirs
        }
        return CloudSave(progression: progression.merged(with: other.progression),
                         wallet: wallet.merged(with: other.wallet),
                         journal: journal.merged(with: other.journal),
                         ledger: ledger.merged(with: other.ledger),
                         companion: companion,
                         // A phone still on the default look takes the saved one.
                         showcase: (showcase == nil || showcase == ProfileShowcase()) ? (other.showcase ?? showcase) : showcase,
                         savedAt: max(savedAt, other.savedAt))
    }
}
