import Foundation

/// Everything personal that should follow an account to a new phone: the
/// Apple Health progression, wallet, journal, reward ledger and companion.
/// Demo-mode data is never saved to the cloud.
public struct CloudSave: Codable, Hashable, Sendable {
    /// 2: wallets keep coins by key (see `WalletState`). Older app versions
    /// leave a schema 2 save alone instead of overwriting it.
    public static let currentSchema = 2

    public var schema: Int
    public var progression: ProgressionState
    public var wallet: WalletState
    public var journal: JourneyJournal
    public var ledger: RewardLedger
    public var companion: CompanionState?
    /// Profile look. Nil in saves from before titles existed.
    public var showcase: ProfileShowcase?
    /// Wildlife and treasures. Nil in saves from before collections existed.
    public var collections: CollectionState?
    /// Companions resting at camp. Nil in saves from before you could own several.
    public var companionRoster: CompanionRoster?
    public var savedAt: Date

    public init(progression: ProgressionState, wallet: WalletState, journal: JourneyJournal, ledger: RewardLedger,
                companion: CompanionState?, showcase: ProfileShowcase? = nil, collections: CollectionState? = nil,
                companionRoster: CompanionRoster? = nil, savedAt: Date) {
        schema = Self.currentSchema
        self.progression = progression
        self.wallet = wallet
        self.journal = journal
        self.ledger = ledger
        self.companion = companion
        self.showcase = showcase
        self.collections = collections
        self.companionRoster = companionRoster
        self.savedAt = savedAt
    }

    /// This device's save combined with another one. Nothing earned on either
    /// side is lost; see each type's `merged(with:)` for the rules.
    public func merged(with other: CloudSave) -> CloudSave {
        let progression = progression.merged(with: other.progression)
        let companions = CompanionRoster.merge((companion, companionRoster ?? CompanionRoster()),
                                               (other.companion, other.companionRoster ?? CompanionRoster()),
                                               lifetimeMeters: progression.lifetimeMeters)
        return CloudSave(progression: progression,
                         wallet: wallet.merged(with: other.wallet),
                         journal: journal.merged(with: other.journal),
                         ledger: ledger.merged(with: other.ledger),
                         companion: companions.active,
                         // A phone still on the default look takes the saved one.
                         showcase: (showcase == nil || showcase == ProfileShowcase()) ? (other.showcase ?? showcase) : showcase,
                         collections: (collections ?? CollectionState()).merged(with: other.collections ?? CollectionState()),
                         companionRoster: companions.roster.resting.isEmpty ? nil : companions.roster,
                         savedAt: max(savedAt, other.savedAt))
    }
}
