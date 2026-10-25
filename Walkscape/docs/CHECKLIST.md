# Walkscape task checklist

Legend: ✅ done · 🔶 done but unverified on device · ⬜ to do

## Milestone 1: Foundation
- ✅ Environment inspected (Linux container, no Xcode → package tests in Docker; iOS build in CI)
- ✅ Architecture: WalkscapeKit package + SwiftUI app target, XcodeGen project
- ✅ Design tokens, panels, pixel buttons, progress bar, chips
- ✅ Four-tab navigation (Journey, Friends, World, Profile)
- ✅ Journey screen: animated parallax scene, distance/steps, next-km progress, trail strip, next-zone preview, friends preview, data-source + last-updated chip
- ✅ Original pixel art: 6 avatars with walk cycle, 16 icons, 10 biome scenes, app icon
- 🔶 Build verified by CI on macOS (check the latest workflow run)

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
- ⬜ Supabase project, auth (Sign in with Apple)
- ⬜ Migrations: profiles, friendships, daily_progress, zone_definitions, user_discoveries, achievements, user_achievements
- ⬜ RLS policies + cross-user access tests
- ⬜ Idempotent daily-progress upsert RPC with plausibility limits
- ⬜ `SupabaseFriendRepository` replacing `MockFriendRepository`
- ⬜ Account deletion, sign-out

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
