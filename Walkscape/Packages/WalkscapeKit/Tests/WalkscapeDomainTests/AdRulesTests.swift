import XCTest
@testable import WalkscapeDomain

final class AdRulesTests: XCTestCase {
    let installed = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60
    let today = LocalDay(year: 2026, month: 10, day: 29)

    var afterGrace: Date { installed.addingTimeInterval(5 * 24 * hour) }

    func testRewardedAdsAreWorthLessThanTheWalkTheyCouldReplace() {
        let rules = AdRules.standard
        XCTAssertEqual(rules.rewardedCoins, 15)
        XCTAssertEqual(rules.rewardedPerDay, 3)
        XCTAssertLessThan(rules.rewardedCoins * rules.rewardedPerDay, 5 * CoinRules.standard.coinsPerKilometre)
    }

    func testNoAppOpenAdsDuringOnboardingOrTheGracePeriod() {
        let state = AdState(firstLaunch: installed)
        XCTAssertFalse(state.mayShowAppOpenAd(now: installed.addingTimeInterval(hour), timeAway: nil, isOnboarded: true))
        XCTAssertFalse(state.mayShowAppOpenAd(now: afterGrace.addingTimeInterval(-60), timeAway: nil, isOnboarded: true))
        XCTAssertFalse(state.mayShowAppOpenAd(now: afterGrace, timeAway: nil, isOnboarded: false))
        XCTAssertTrue(state.mayShowAppOpenAd(now: afterGrace, timeAway: nil, isOnboarded: true))
    }

    func testQuickGlancesNeverShowAnAd() {
        let state = AdState(firstLaunch: installed)
        XCTAssertFalse(state.mayShowAppOpenAd(now: afterGrace, timeAway: 20, isOnboarded: true))
        XCTAssertTrue(state.mayShowAppOpenAd(now: afterGrace, timeAway: 90, isOnboarded: true))
    }

    func testAtMostOneAppOpenAdEveryFourHours() {
        var state = AdState(firstLaunch: installed)
        state.recordAppOpenAd(at: afterGrace)
        XCTAssertFalse(state.mayShowAppOpenAd(now: afterGrace.addingTimeInterval(3.9 * hour), timeAway: nil, isOnboarded: true))
        XCTAssertTrue(state.mayShowAppOpenAd(now: afterGrace.addingTimeInterval(4 * hour), timeAway: nil, isOnboarded: true))
    }

    func testThreeRewardedAdsPerDayThenTheLimitResetsTomorrow() {
        var state = AdState(firstLaunch: installed)
        XCTAssertEqual(state.rewardedAdsLeft(on: today), 3)
        XCTAssertEqual(state.recordRewardedAd(on: today), 15)
        XCTAssertEqual(state.recordRewardedAd(on: today), 15)
        XCTAssertEqual(state.recordRewardedAd(on: today), 15)
        XCTAssertEqual(state.rewardedAdsLeft(on: today), 0)
        XCTAssertNil(state.recordRewardedAd(on: today))

        let tomorrow = LocalDay(year: 2026, month: 10, day: 30)
        XCTAssertEqual(state.rewardedAdsLeft(on: tomorrow), 3)
        XCTAssertEqual(state.recordRewardedAd(on: tomorrow), 15)
        XCTAssertEqual(state.rewardedAdsLeft(on: tomorrow), 2)
    }

    func testAdRewardsAddToTheWallet() {
        var wallet = WalletState(rules: CoinRules(starterCoins: 0))
        wallet.earnAdReward(15)
        XCTAssertEqual(wallet.coins, 15)
        XCTAssertEqual(wallet.lifetimeCoins, 15)
    }

    func testStateSurvivesSaving() throws {
        var state = AdState(firstLaunch: installed)
        _ = state.recordRewardedAd(on: today)
        state.recordAppOpenAd(at: afterGrace)
        let decoded = try JSONDecoder().decode(AdState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}
