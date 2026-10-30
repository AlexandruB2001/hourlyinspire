# Walkscape task checklist

Legend: ✅ done · 🔶 done but unverified on device · ⬜ to do

## Milestone 1: Foundation
- ✅ Environment inspected (Linux container, no Xcode → package tests in Docker; iOS build in CI)
- ✅ Architecture: WalkscapeKit package + SwiftUI app target, XcodeGen project
- ✅ Design tokens, panels, pixel buttons, progress bar, chips
- ✅ Four-tab navigation (Journey, Friends, World, Profile)
- ✅ Journey screen: animated parallax scene, distance/steps, next-km progress, trail strip, next-zone preview, friends preview, data-source + last-updated chip
- ✅ Original pixel art: 6 avatars with walk cycle, 16 icons, 10 biome scenes, app icon
- ✅ iOS app compiles (Xcode 16.4, iOS simulator SDK 18.5) in CI on macOS; not yet run in a simulator or on a device

## Milestone 2: Walking
- ✅ `WalkingDataProvider` protocol; mock and HealthKit implementations
- ✅ Statistics queries, local-day boundaries, permission, no-data, error and stale states
- ✅ Estimated distance from steps (labelled, unranked)
- ✅ Zone progression engine: integer metres, idempotent unlocks, collapsed celebrations, late updates
- ✅ Celebration banner with haptics
- 🔶 Background delivery via `HKObserverQuery` (needs device testing)
- ⬜ Test on device: permission flow, denied access, Watch + iPhone overlap, midnight rollover, DST, travel across time zones

## Milestone 3: Social track
- ✅ Layout engine: cluster fitting, min/max span, lanes, nudging, hysteresis
- ✅ Edge indicators with grouping; "You" badge when off-screen
- ✅ Focus a friend (indicator, tap, or leaderboard), focus card with comparison, Back to me
- ✅ Drag to explore (free focus not recentred by refreshes)
- ✅ Leaderboard with ties, estimated and no-data states
- ✅ Friend requests, add-friend sheet, remove and block (mock)
- ✅ Layout unit tests (all cases from the brief)

## Milestone 4: Backend
- ✅ Migrations: profiles, friendships, blocks, daily_progress, zone_definitions, user_discoveries, achievements, user_achievements
- ✅ RLS policies + 64 database tests (cross-user access, friendship rules, validation, idempotent sync, blocking, deletion)
- ✅ Idempotent daily-progress upsert with plausibility limits
- ✅ Dependency-free Swift client: Apple ID-token sign-in, token refresh, RPC, error mapping (17 tests)
- ✅ `SupabaseFriendRepository`; sample friends only when no backend is configured
- ✅ Sign in with Apple, sign-out, account deletion, username/avatar/sharing sync
- ✅ Daily totals sync after each Health refresh (never demo data; skipped when unchanged or sharing is off)
- ✅ Supabase project `walkscape` set up: schema applied and verified, Apple sign-in enabled, app pointed at it
- ⬜ End-to-end test on device with two accounts
- ⬜ Sync discoveries/achievements to the server

## Milestone 5: Game progression
- ✅ 20 zones: ten more down the far side of the Summit to Lighthouse Point, with new scenes, discoveries and achievements
- ✅ Coins: 10 per kilometre each day, plus 2 hidden chests per kilometre (5 coins each, tap to open on the Journey screen)
- ✅ Shop: 30 outfit items (hats, glasses, scarves, shoes, backs) in 4 rarities, 50-coin mystery box, wear/unwear
- ✅ World tab: browse earlier days (Apple Health totals, read-only, never re-rewarded)
- ✅ Journey journal: permanent, de-duplicated log of zones, relics, distance milestones, companion growth, team and referral events
- ✅ Starter companions (Mossling, Emberfox, Moonmoth) that grow with real walking: a detail per km, new shapes at 5/20/50/100 km
- ✅ Shareable milestone cards (current progress or any journal entry) via the share sheet / Save Image
- ✅ Ads (AdMob): app-open ad at most every 4 hours, none in the first 5 days or after a quick glance (<1 min away); rewarded ads for 15 coins, 3 per day; UMP consent + ATT
- ✅ Ads: real AdMob ids in `Config/Base.xcconfig` (used only by App Store builds; TestFlight shows test ads)
- ⬜ Ads: App Store privacy label, `app-ads.txt` on a developer website, GDPR message in AdMob → Privacy & messaging
- ✅ Friend day card: tap a walker on the Journey leaderboard for their distance, steps, zone, last update and how far ahead or behind you they are
- ✅ Local notifications: chests, zones, relics, achievements, companion growth, referral chests, daily reminder (Profile → Notifications)
- 🔶 Push notifications for friend requests and team invites: APNs key, `send-push` and webhooks set up; delivery to a real device not yet confirmed
- ✅ Explorer Levels: lifetime XP from walking (capped 25 km/day), zones, relics, achievements and rewards; 25 coins per level; level-up banner and Journal entry
- ✅ Reward ledger: every quest/event/level reward has an id and pays once
- ✅ Quests: 3 daily (reset at local midnight), 3 weekly + 1 companion (reset Monday), weekly chest for finishing every weekly quest; rewards paid once via the ledger; Journey card + quest log
- ⬜ Quest rewards beyond coins/XP (exclusive cosmetics, postcards, collection items) arrive with collections in Phase 3
- ✅ Titles (20) and profile frames (8), unlocked from Apple Health progress; favourite-zone backdrop, companion and up to 3 showcased achievements; titles shown under names on the leaderboard, team list and friend card (migration 20261101000001)
- ✅ Collections (World tab): Relics, 27 Wildlife (deterministic daily sightings by rarity in zones reached that day), 12 Postcards (return visits), 8 Treasures (trail chests 4 %, weekly chest), 12 Memories (from walking history); filters, detail cards, discovery dates, completion rewards at 25/50/75/100 %; collection titles
- ✅ World events: 12 events (shooting star, merchant, fireflies, rainbow, footprints, forest spirit, lost chest, aurora, blossom festival, harvest moon, whale song, crystal bloom) with zones, rarity, evening/season windows, max 2 a day, fixed per day for everyone, found once per day; Journey card and in-scene marker
- ✅ Seasons: one recolour pass + seasonal weather (snow, leaves, petals, fireflies) for every zone; hemisphere from time zone
- ✅ Companion personalities: daily finds (Mossling stones, Emberfox coins/treasure, Moonmoth night wildlife), voice lines for zones, level-ups and walks, species-specific motion
- ✅ Companion accessories: 10 hats, scarves, bells, backpacks and capes drawn on any species and stage; 7 in the shop, 3 as Explorer Level gifts (5, 10, 15)
- ✅ Shared discoveries: friends finding the same event or rare creature on the same day both get a Journal entry and 25 coins (migration 20261102000001)
- ✅ Friend milestones feed with reactions (🎉 👏 ⭐ 💛), and rewards for 100/250/500 km walked together with a friend
- ✅ Team ledger: every member's day credited to one team once (capped 25 km), kept when they leave; expeditions and totals never go backwards (migration 20261103000001)
- ✅ Team Campfire: 5 levels (campfire → tent & lantern → gathering place → camp village → expedition HQ) from team distance + expeditions, 10 shared decorations, contributor list, per-player level rewards
- ✅ Team worlds (Phase 7): 5 worlds of 4-5 zones each opening after the Summit Relay, world tint art, world map, weekly community challenge per world; rewards once per player who walked 2 km for the team
- ✅ Team worlds, second pass:
  - hand-painted background per world
  - 3 creatures per world
  - world quests (Pathfinder, World Naturalist with a world treasure)
  - a title per world
  - full-screen zone arrival
  - server-recorded unlocks (migration 20261106)
- ⏸ Store and Walkscape Plus are built but hidden (`StoreFeature.isEnabled = false`) until the owner turns them on
- ✅ Seasonal festivals (Phase 8): Great Harvest, Winter Wanderer, Spring Awakening, Ocean Expedition, Starfall Festival; yearly dates, 4 tiers (≤ 50 km, 10 km/day cap), festival quests, exclusive companion accessories (sold after the festival), festival titles, community goal (migration 20261104000001)
- ✅ Store (Phase 9, code): Walkscape Plus ($2.99/mo, $19.99/yr) and 4 cosmetic bundles via StoreKit 2; server-verified purchases (migration 20261105000001, verify-purchase + app-store-notifications functions); premium outfits, companion skins, trails, Journal themes, Plus frames, campsite decor, monthly Plus gift
- ✅ Store server: purchases migration applied, verify-purchase and app-store-notifications deployed (2026-10-30)
- ✅ Store: 6 products created in App Store Connect; Server Notification URLs (production + sandbox) set
- ⬜ Store: Paid Apps agreement + bank/tax (owner), then sandbox purchase/restore/refund test
- ✅ Cloud save (migration 20261031000001, live)
- ✅ Referrals: invite codes, server-side qualification (5 km over 2 days), 25–100 coin referral chest
- ✅ Teams: create/join/invite, member day/week totals, weekly standings, expeditions, badges
- ✅ `20261027000001` and `20261028000001` applied to the live project on 2026-10-28 (20 zones, 12 achievements, 20 policies)
- ⬜ Referral fraud hardening: Apple-ID-level duplicate detection (auth.identities) and/or DeviceCheck
- ✅ Coins and items sync through the cloud save; every coin earned or spent has a key, so merging two phones never duplicates or loses coins (cloud save schema 2)
- ✅ Distance typed into the Health app by hand doesn't count (only device-recorded samples)
- ⬜ Server-authoritative coins (today the client and its cloud save are trusted)
- ⬜ Richer scenes: day/night tint, more wildlife, zone-specific particles
- ⬜ Achievement unlock toasts
- ⬜ Local notifications (daily reminder, friend passed you)

## Milestone 6: Beta
- ✅ TestFlight workflow (automatic signing via App Store Connect API key) + privacy manifest
- ✅ API key + GitHub secrets + App Store Connect app record (docs/TESTFLIGHT.md)
- ⬜ Physical-device test pass, offline/stale states, relaunch persistence
- ⬜ Accessibility audit (VoiceOver, Dynamic Type at XXL)
- ✅ TestFlight (build 3 installed and played on device)

## Milestone 7: Monetisation
- ⬜ Walkscape Plus (StoreKit 2): cosmetics only, never extra distance
