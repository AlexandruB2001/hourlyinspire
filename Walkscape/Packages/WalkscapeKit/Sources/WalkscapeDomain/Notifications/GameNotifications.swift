import Foundation

/// A notification the game wants to show. The app turns it into a local
/// notification; the server sends the social ones as push notifications.
public struct GameNotification: Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        /// Chests, zones, relics, achievements, companion growth, referral chests.
        case rewards
        /// Friend requests and team invites.
        case social
        /// The optional daily walk reminder.
        case reminder
    }

    /// Where tapping the notification takes you.
    public enum Destination: String, Codable, Sendable {
        case journey, friends, shop, profile
    }

    /// Stable per event, so the same event is never announced twice.
    public let id: String
    public let category: Category
    public let title: String
    public let body: String
    public let destination: Destination

    public init(id: String, category: Category, title: String, body: String, destination: Destination) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.destination = destination
    }
}

/// Which kinds of notification the player wants. Everything is on by default
/// except the reminder; nothing is shown until iOS permission is granted.
public struct NotificationPreferences: Codable, Hashable, Sendable {
    public var rewards: Bool
    public var social: Bool
    public var dailyReminder: Bool
    /// Hour of the day (local time) for the reminder.
    public var reminderHour: Int

    public init(rewards: Bool = true, social: Bool = true, dailyReminder: Bool = false, reminderHour: Int = 18) {
        self.rewards = rewards
        self.social = social
        self.dailyReminder = dailyReminder
        self.reminderHour = min(23, max(0, reminderHour))
    }

    public func allows(_ category: GameNotification.Category) -> Bool {
        switch category {
        case .rewards: return rewards
        case .social: return social
        case .reminder: return dailyReminder
        }
    }
}

/// Remembers which events were already announced, so a refresh in the
/// background never repeats a notification.
public struct NotificationLedger: Codable, Hashable, Sendable {
    public private(set) var announcedIDs: [String]
    /// Oldest ids are forgotten past this; events this old are never re-announced anyway.
    public static let capacity = 500

    public init() { announcedIDs = [] }

    /// The notifications not announced yet, recording them as announced.
    public mutating func unannounced(_ notifications: [GameNotification]) -> [GameNotification] {
        var seen = Set(announcedIDs)
        let fresh = notifications.filter { seen.insert($0.id).inserted }
        announcedIDs.append(contentsOf: fresh.map(\.id))
        if announcedIDs.count > Self.capacity { announcedIDs.removeFirst(announcedIDs.count - Self.capacity) }
        return fresh
    }

    /// Marks events as seen without announcing them (e.g. everything that
    /// already existed when notifications were first turned on).
    public mutating func markSeen(_ notifications: [GameNotification]) {
        _ = unannounced(notifications)
    }
}

/// Builds the notification text for each game event. Pure, so the wording
/// and ids are tested.
public enum GameNotifications {
    /// More than this many rewards at once are folded into one summary.
    public static let maxRewardsAtOnce = 3

    public static func chests(_ count: Int, on day: LocalDay, total: Int, rules: CoinRules = .standard) -> GameNotification? {
        guard count > 0 else { return nil }
        let title = count == 1 ? "You found a chest!" : "You found \(count) chests!"
        return GameNotification(id: "chest-\(day.isoString)-\(total)", category: .rewards, title: title,
                                body: "Claim it now for \(rules.coinsPerChest) coins each.", destination: .journey)
    }

    public static func journal(_ entry: JournalEntry) -> GameNotification {
        let destination: GameNotification.Destination
        switch entry.kind {
        case .referral: destination = .journey
        case .team, .expedition: destination = .friends
        case .achievement: destination = .profile
        default: destination = .journey
        }
        let title: String
        switch entry.kind {
        case .companion: title = entry.title
        case .zone: title = "New zone: \(entry.title.replacingOccurrences(of: "Reached ", with: ""))"
        case .relic: title = entry.title
        case .achievement: title = "Achievement unlocked: \(entry.title)"
        default: title = entry.title
        }
        return GameNotification(id: "journal-\(entry.id)", category: .rewards, title: title,
                                body: entry.detail, destination: destination)
    }

    /// New journal entries, at most `maxRewardsAtOnce`, or one summary when there are more.
    public static func journal(_ entries: [JournalEntry], on day: LocalDay) -> [GameNotification] {
        guard entries.count > maxRewardsAtOnce else { return entries.map(journal) }
        let ids = entries.map(\.id).sorted().joined(separator: ",")
        return [GameNotification(id: "journal-summary-\(day.isoString)-\(ids.hashValueStable)", category: .rewards,
                                 title: "\(entries.count) new milestones!",
                                 body: "Open your Journey Journal to see everything you found.", destination: .journey)]
    }

    public static func questComplete(_ status: QuestStatus) -> GameNotification {
        GameNotification(id: "quest-done-\(status.rewardID)", category: .rewards, title: "Quest complete!",
                         body: "\(status.quest.title). Claim \(status.quest.coins) coins and \(status.quest.xp) XP.",
                         destination: .journey)
    }

    public static func referralChest(_ chest: ReferralChest) -> GameNotification {
        GameNotification(id: "referral-chest-\(chest.id)", category: .rewards, title: "A friend you invited is walking!",
                         body: "Your referral chest is ready. Claim it now.", destination: .journey)
    }

    public static func friendRequest(_ request: FriendRequest) -> GameNotification {
        GameNotification(id: "friend-request-\(request.id)", category: .social, title: "New friend request",
                         body: "@\(request.username) wants to walk with you.", destination: .friends)
    }

    public static func teamInvite(_ invite: TeamInvite) -> GameNotification {
        GameNotification(id: "team-invite-\(invite.id)", category: .social, title: "Team invite",
                         body: "@\(invite.fromUsername) invited you to join \(invite.teamName).", destination: .friends)
    }

    public static func dailyReminder(companionName: String?) -> GameNotification {
        let body = companionName.map { "\($0) is ready for a walk. Every step counts!" }
            ?? "Your trail is waiting. Every step counts!"
        return GameNotification(id: "daily-reminder", category: .reminder, title: "Time for a walk?",
                                body: body, destination: .journey)
    }
}

extension String {
    /// FNV-1a, stable across launches (unlike `hashValue`).
    var hashValueStable: String {
        var hash: UInt64 = 1469598103934665603
        for byte in utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}
