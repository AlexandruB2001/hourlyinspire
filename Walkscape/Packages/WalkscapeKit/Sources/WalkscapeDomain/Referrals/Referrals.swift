import Foundation

/// The rules the server enforces for referrals. Kept here so the app can
/// explain them; the database functions are the source of truth.
public enum ReferralRules {
    /// The invited walker must enter the code within this many days of creating their account.
    public static let redeemWithinDays = 14
    /// ...then walk this far in total...
    public static let qualifyingMeters = 5_000
    /// ...on at least this many different days...
    public static let qualifyingDays = 2
    /// ...within this many days of entering the code.
    public static let qualifyingWindowDays = 30
    public static let minimumCoins = 25
    public static let maximumCoins = 100

    public static var summary: String {
        "When a friend joins with your code and walks \(DistanceFormatting.kilometres(qualifyingMeters)) "
            + "over \(qualifyingDays) different days within \(qualifyingWindowDays) days, "
            + "you get a referral chest with \(minimumCoins)–\(maximumCoins) coins."
    }

    /// Codes are 8 letters/digits; entry is forgiving about case and spaces.
    public static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

public struct ReferralInvitee: Identifiable, Hashable, Sendable {
    public let id: String
    public let username: String
    public let qualified: Bool
    /// 0...1 toward the walking requirement.
    public let progress: Double

    public init(id: String, username: String, qualified: Bool, progress: Double) {
        self.id = id
        self.username = username
        self.qualified = qualified
        self.progress = min(1, max(0, progress))
    }
}

public struct ReferralStatus: Hashable, Sendable {
    /// The caller's own code to share.
    public let code: String
    /// Whether the caller already used someone else's code.
    public let hasRedeemedCode: Bool
    /// False once the caller's account is too old to redeem a code.
    public let canRedeemCode: Bool
    public let invitees: [ReferralInvitee]

    public init(code: String, hasRedeemedCode: Bool, canRedeemCode: Bool, invitees: [ReferralInvitee]) {
        self.code = code
        self.hasRedeemedCode = hasRedeemedCode
        self.canRedeemCode = canRedeemCode
        self.invitees = invitees
    }
}

public enum ReferralError: Error, Hashable, Sendable {
    case notSignedIn
    case codeNotFound
    case ownCode
    case alreadyRedeemed
    case accountTooOld
    case circular
    case network(String)
}

public protocol ReferralRepository: Sendable {
    func status() async throws -> ReferralStatus
    func redeem(code: String) async throws
    /// Chests for invitees who met the requirement and haven't been opened yet.
    func readyChests() async throws -> [ReferralChest]
    func markOpened(_ chest: ReferralChest) async throws
}
