import XCTest
@testable import WalkscapeDomain

final class SocialTests: XCTestCase {
    let day = LocalDay(year: 2026, month: 11, day: 2)

    func testOnlySpecialFindsAreRecordedForSharing() {
        let zones = ZoneCatalog.standard.zones.map(\.id)
        var sawCommon = false
        for offset in 0..<60 {
            let d = day.adding(days: offset)
            let records = SharedDiscoveries.records(on: d, zonesReached: zones, foundEvents: [])
            for record in records {
                XCTAssertGreaterThanOrEqual(WildlifeCatalog.creature(withID: record.id)!.rarity, .rare)
            }
            sawCommon = sawCommon || WildlifeCatalog.sightings(on: d, zonesReached: zones).contains { $0.rarity == .common }
        }
        XCTAssertTrue(sawCommon, "commons are spotted but not shared")
        let event = ScheduledEvent(event: WorldEventCatalog.event(withID: "forest-spirit")!, day: day, zoneID: "cloud-forest")
        XCTAssertTrue(SharedDiscoveries.records(on: day, zonesReached: [], foundEvents: [event])
            .contains(DiscoveryRecord(id: "forest-spirit", day: day)))
        XCTAssertEqual(SharedDiscoveries.name(of: "forest-spirit"), "Forest Spirit")
    }

    func testSharedDiscoveriesPayOncePerFriend() {
        let a = SharedDiscovery(discoveryID: "spirit", day: day, friendID: "sam", friendName: "sam")
        let b = SharedDiscovery(discoveryID: "spirit", day: day, friendID: "kim", friendName: "kim")
        XCTAssertNotEqual(a.reward.id, b.reward.id)
        var ledger = RewardLedger()
        var wallet = WalletState()
        XCTAssertTrue(ledger.claim(a.reward, into: &wallet))
        XCTAssertFalse(ledger.claim(a.reward, into: &wallet))
        XCTAssertEqual(a.journalEntry.title, "You and @sam found the Forest Spirit!")
    }

    func testMilestonesComeFromTheJournalWithTheirFirstDay() {
        var journal = JourneyJournal()
        journal.record([
            JournalEntry(id: "lifetime-10000", kind: .distance, day: day, title: "", detail: "", iconID: ""),
            JournalEntry(id: "lifetime-25000", kind: .distance, day: day, title: "", detail: "", iconID: ""),
            JournalEntry(id: "day-10000-2026-11-04", kind: .distance, day: day.adding(days: 2), title: "", detail: "", iconID: ""),
            JournalEntry(id: "day-10000-2026-11-03", kind: .distance, day: day.adding(days: 1), title: "", detail: "", iconID: ""),
            JournalEntry(id: "companion-emberfox-2026-10-30-1", kind: .companion, day: day, title: "", detail: "", iconID: ""),
            JournalEntry(id: "companion-emberfox-2026-10-30-adopted", kind: .companion, day: day, title: "", detail: "", iconID: ""),
            JournalEntry(id: "companion-find-2026-11-02", kind: .companion, day: day, title: "", detail: "", iconID: ""),
            JournalEntry(id: "level-12", kind: .level, day: day, title: "", detail: "", iconID: ""),
        ])
        let milestones = Dictionary(uniqueKeysWithValues: FriendMilestoneCatalog.milestones(in: journal).map { ($0.id, $0.day) })
        XCTAssertEqual(Set(milestones.keys), ["total-10k", "day-10k", "companion-sprout", "level-10"])
        XCTAssertEqual(milestones["day-10k"], day.adding(days: 1), "the first 10 km day counts")
        for id in milestones.keys { XCTAssertNotNil(FriendMilestoneCatalog.phrases[id], id) }
    }

    func testWalkedTogetherRewardsStepUp() {
        XCTAssertEqual(WalkedTogether.rewards(friendID: "sam", meters: 99_000), [])
        XCTAssertEqual(WalkedTogether.rewards(friendID: "sam", meters: 260_000).map(\.id), ["together-100k-sam", "together-250k-sam"])
    }
}
