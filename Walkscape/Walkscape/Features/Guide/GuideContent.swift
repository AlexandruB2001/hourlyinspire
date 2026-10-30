import Foundation
import WalkscapeDomain

/// One topic of the Walkscape Guide.
struct GuideSection: Identifiable, Hashable {
    enum ID: String, CaseIterable {
        case journey, chests, shop, companions, friends, teams, quests, collections
    }

    struct Entry: Hashable {
        let title: String
        let body: String
    }

    let id: ID
    let title: String
    let spriteID: String
    let entries: [Entry]
}

/// The guide's text. Numbers come from the game's own rules, so the guide
/// stays right when they change; edit the words here to update it.
enum GuideContent {
    static func sections() -> [GuideSection] {
        [journey, chests, shop, companions, friends, teams, quests, collections]
    }

    static func section(_ id: GuideSection.ID) -> GuideSection {
        sections().first { $0.id == id }!
    }

    private static let coins = CoinRules.standard
    private static let explorer = ExplorerRules.standard
    private static let ads = AdRules.standard

    private static func km(_ meters: Int) -> String {
        meters % 1_000 == 0 ? "\(meters / 1_000) km" : String(format: "%.1f km", Double(meters) / 1_000)
    }

    static let journey = GuideSection(id: .journey, title: "Your Journey", spriteID: "boot", entries: [
        .init(title: "Walking moves you",
              body: "Walkscape reads your steps and walking + running distance from Apple Health. Every metre you walk in real life moves your walker along today's trail. Nothing is written to Health and no location is used."),
        .init(title: "What counts",
              body: "Walking your iPhone or Apple Watch records counts. Distance typed into the Health app by hand doesn't. If Health has steps but no distance, Walkscape estimates the distance from your steps."),
        .init(title: "Twenty zones a day",
              body: "Each day starts at the Sunny Meadow. Every kilometre takes you into the next zone: up to the Summit, down the far side and on to Lighthouse Point, 20 zones in all. The first time you reach a zone you find its relic."),
        .init(title: "After Lighthouse Point",
              body: "Past the 20th zone the road keeps going: every extra kilometre adds a new stretch of Wanderer's Road."),
        .init(title: "When the day resets",
              body: "Your trail starts again at local midnight, in your iPhone's time zone. Relics, coins, items, your companion and everything you've collected are kept forever."),
        .init(title: "Explorer Level",
              body: "You earn XP for walking (\(explorer.xpPerKilometre) XP a kilometre, counting up to \(km(explorer.dailyXPCapMeters)) a day), new zones, relics, achievements, quests and other rewards. Each new level pays \(explorer.coinsPerLevel) coins."),
    ])

    static let chests = GuideSection(id: .chests, title: "Chests & Coins", spriteID: "chest", entries: [
        .init(title: "Coins for walking",
              body: "Every whole kilometre you walk in a day earns \(coins.coinsPerKilometre) coins."),
        .init(title: "Trail chests",
              body: "\(coins.chestsPerKilometre) chests are hidden along each kilometre of today's walk. When you pass one, it bounces on the Journey scene: tap it to open it for \(coins.coinsPerChest) coins. About \(Int(TreasureCatalog.chestTreasureChance * 100)) in 100 chests also hold a treasure."),
        .init(title: "Once per chest",
              body: "Each chest belongs to the day and spot you found it, and can be opened once. Unopened chests wait for you, even after midnight."),
        .init(title: "Other ways to earn",
              body: "Quests, Explorer levels, collection milestones, festivals, team worlds and friends' invites all pay coins. In the Shop you can also watch a short ad for \(ads.rewardedCoins) coins, up to \(ads.rewardedPerDay) times a day."),
        .init(title: "Spending coins",
              body: "Coins buy outfits for your walker, accessories for your companion and Mystery Boxes in the Shop."),
    ])

    static let shop = GuideSection(id: .shop, title: "Items & Shop", spriteID: "mystery-box", entries: [
        .init(title: "Outfits",
              body: "\(ShopCatalog.items.count) outfit pieces (hats, glasses, scarves, shoes and backs) in four rarities: common \(Rarity.common.price), rare \(Rarity.rare.price), epic \(Rarity.epic.price) and legendary \(Rarity.legendary.price) coins. Tap one you own to wear it."),
        .init(title: "Mystery Box",
              body: "For \(ShopCatalog.mysteryBoxPrice) coins you get a random outfit piece you don't own yet. Odds by rarity: common \(Rarity.common.mysteryBoxWeight)%, rare \(Rarity.rare.mysteryBoxWeight)%, epic \(Rarity.epic.mysteryBoxWeight)%, legendary \(Rarity.legendary.mysteryBoxWeight)%."),
        .init(title: "Companion accessories",
              body: "Hats, scarves, bells, backpacks and capes for your companion. Some are sold for coins, some are gifts for reaching Explorer levels, and festival ones are earned during the festival."),
        .init(title: "Cosmetic only",
              body: "Everything in the Shop changes how things look. Nothing you buy moves you further, earns extra distance or changes your rewards: progress only ever comes from walking."),
    ])

    static let companions = GuideSection(id: .companions, title: "Companions", spriteID: "egg", entries: [
        .init(title: "Your walking buddy",
              body: "On your first launch you pick a companion: Mossling, Emberfox or Moonmoth. It walks beside you on the Journey scene."),
        .init(title: "Growing up",
              body: "Your companion grows with the distance you walk together. It gains a little detail every kilometre and a new shape at " +
                    CompanionGrowth.Stage.allCases.dropFirst().map { "\($0.startKilometres) km (\($0.name))" }.joined(separator: ", ") + "."),
        .init(title: "Personality",
              body: "Each species has its own habits: some days your companion finds something on the walk, like a stone, coins or a creature, and it chats about zones and milestones."),
        .init(title: "Accessories",
              body: "Dress your companion from the Shop. Accessories show on every growth stage."),
    ])

    static let friends = GuideSection(id: .friends, title: "Friends", spriteID: "compass", entries: [
        .init(title: "Adding friends",
              body: "Sign in with Apple in the Friends tab, then add friends by their username. They accept your request before you can see each other. You can also share your invite code from your Profile."),
        .init(title: "The friend track",
              body: "The Friends tab shows today's walk as a shared track. Everyone appears at today's distance, so friends who've walked about as far as you are bunched up next to you. Tap someone to see their day."),
        .init(title: "What friends see",
              body: "Only your daily totals and profile are shared, and only with friends you've accepted. You can stop sharing in your Profile."),
        .init(title: "Milestones & reactions",
              body: "Friends' milestones show in a feed where you can react with 🎉 👏 ⭐ 💛. Walking " +
                    WalkedTogether.milestones.map { km($0) }.joined(separator: ", ") + " on the same days as a friend earns rewards."),
        .init(title: "Shared discoveries",
              body: "If you and a friend find the same world event or rare creature on the same day, you both get a Journal entry and 25 coins."),
    ])

    static let teams = GuideSection(id: .teams, title: "Teams & Team Worlds", spriteID: "team-badge", entries: [
        .init(title: "Joining a team",
              body: "In the Friends tab, create a team, join one with its code, or accept an invite from a friend. You can be in one team at a time."),
        .init(title: "Team distance",
              body: "From the day you join, each day's walk counts for your team, up to 25 km a person per day. A day only ever counts for one team, and what you walked stays with the team if you leave, so the team total never goes down."),
        .init(title: "Expeditions",
              body: "Your team works through expeditions together: " +
                    ExpeditionCatalog.all.map { "\($0.name) (\(km($0.goalMeters)))" }.joined(separator: ", ") + ". Each one earns a team badge."),
        .init(title: "The Team Campfire",
              body: "Your camp grows with team distance and expeditions, from " +
                    CampfireCatalog.levels.map(\.name).joined(separator: " to ") + ". Members place decorations as the camp levels up."),
        .init(title: "Team Worlds",
              body: "When your team finishes the Summit Relay (\(km(TeamWorldCatalog.startMeters(of: TeamWorldCatalog.worlds[0]))) of team walking in all), the first of \(TeamWorldCatalog.worlds.count) team worlds opens: " +
                    TeamWorldCatalog.worlds.map(\.name).joined(separator: ", ") + ". Each world's zones open as the team walks further."),
        .init(title: "World rewards",
              body: "Reaching a zone gives every member who has walked at least \(km(TeamWorldCatalog.minimumContribution)) for the team its relic, coins and XP, once per player. Each world has its own wildlife (spotted by members who walked \(km(TeamWorldCatalog.sightingMinimumMeters)) that day), world quests, a weekly team challenge and a title."),
    ])

    static let quests = GuideSection(id: .quests, title: "Quests & Events", spriteID: "medal", entries: [
        .init(title: "Daily quests",
              body: "\(QuestCatalog.dailyCount) new quests every day at local midnight, like walking a distance or opening a chest. Tap Claim when one is done to collect its coins and XP."),
        .init(title: "Weekly quests",
              body: "\(QuestCatalog.weeklyCount) weekly quests plus a companion quest, new every Monday. Finish all of the weekly ones to open the weekly chest."),
        .init(title: "World events",
              body: "Some days something special happens in a zone: a shooting star, a travelling merchant, an aurora and more. They're the same for every player that day. Walk to that zone to find it."),
        .init(title: "Festivals",
              body: "Five festivals come round each year: " + SeasonalEventCatalog.all.map(\.name).joined(separator: ", ") +
                    ". While one is on, your walking fills its reward tiers (up to \(km(EventProgress.dailyCapMeters)) a day counts) and it has its own quests, accessories and a title."),
    ])

    static let collections = GuideSection(id: .collections, title: "Collections & Discoveries", spriteID: "journal", entries: [
        .init(title: "Relics",
              body: "One in each of the 20 trail zones, found the first time you reach it."),
        .init(title: "Wildlife",
              body: "\(WildlifeCatalog.all.count) creatures live in the zones. Each day some of them can be spotted in the zones you reach: rare ones less often."),
        .init(title: "Postcards",
              body: "\(PostcardCatalog.all.count) postcards, earned by coming back to the same zone on different days."),
        .init(title: "Treasures",
              body: "\(TreasureCatalog.all.count) treasures, found now and then in trail chests and the weekly chest."),
        .init(title: "Memories",
              body: "Moments from your own walking history, like your first 5 km day or 10 km walked in total."),
        .init(title: "Where to find them",
              body: "Open the Collection from the World tab. Each book pays rewards at " +
                    CollectionProgress.milestones.map { "\($0)%" }.joined(separator: ", ") + " complete."),
        .init(title: "Your Journal",
              body: "The Journal at the bottom of the Journey tab keeps every zone, relic, creature, milestone and team moment, day by day."),
    ])
}
