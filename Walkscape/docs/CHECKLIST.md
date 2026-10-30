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
- ⬜ Ads: real AdMob ids in `Config/Base.xcconfig`, App Store privacy label, `app-ads.txt` on a developer website, GDPR message in AdMob → Privacy & messaging
- ✅ Friend day card: tap a walker on the Journey leaderboard for their distance, steps, zone, last update and how far ahead or behind you they are
- ✅ Local notifications: chests, zones, relics, achievements, companion growth, referral chests, daily reminder (Profile → Notifications)
- ⬜ Push notifications for friend requests and team invites: code, migration and Edge Function are in the repo; needs an APNs key and the setup in BACKEND.md
- ✅ Referrals: invite codes, server-side qualification (5 km over 2 days), 25–100 coin referral chest
- ✅ Teams: create/join/invite, member day/week totals, weekly standings, expeditions, badges
- ✅ `20261027000001` and `20261028000001` applied to the live project on 2026-10-28 (20 zones, 12 achievements, 20 policies)
- ⬜ Referral fraud hardening: Apple-ID-level duplicate detection (auth.identities) and/or DeviceCheck
- ⬜ Sync coins and owned items to the server (local per data source for now)
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
