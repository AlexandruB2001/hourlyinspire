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
- ⬜ Create the Supabase project, run the migrations, enable the Apple provider, add the GitHub secrets (see docs/BACKEND.md)
- ⬜ End-to-end test on device with two accounts
- ⬜ Sync discoveries/achievements to the server

## Milestone 5: Game progression
- ⬜ More character customisation (hats, colours)
- ⬜ Richer scenes: day/night tint, more wildlife, zone-specific particles
- ⬜ Achievement unlock toasts
- ⬜ Local notifications (daily reminder, friend passed you)

## Milestone 6: Beta
- ⬜ Physical-device test pass, offline/stale states, relaunch persistence
- ⬜ Accessibility audit (VoiceOver, Dynamic Type at XXL)
- ⬜ TestFlight

## Milestone 7: Monetisation
- ⬜ Walkscape Plus (StoreKit 2): cosmetics only, never extra distance
