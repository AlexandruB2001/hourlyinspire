# Walkscape: Journey — Expansion plan

Status: **proposal, nothing implemented yet.** Written 30 October 2026 after an
audit of the codebase at commit `ffeb764` (TestFlight build 6 + the unreleased
friend day card and notifications).

## 1. Audit: what exists today

### Code size
- `WalkscapeKit` package: ~6,500 lines. `WalkscapeDomain` (game rules, pure and
  unit-tested), `PixelArt` (procedural renderer), `WalkscapeBackend` (Supabase
  client), `PixelPreview` (CI art previews).
- App: ~5,800 lines of SwiftUI. One `@Observable AppModel` coordinates
  everything; views are per tab under `Features/`.
- Supabase: 5 migrations, 38 SQL functions, 3 database test files, all run in CI.

### Reusable systems (the expansion builds on these)

| System | Where | Reuse for |
|---|---|---|
| Idempotent progression: `ProgressionState.apply` keeps the *best* distance per day (`dailyBestMeters`), so HealthKit refreshes and downward revisions never re-grant anything | `ZoneProgression/ProgressionState.swift` | XP, quests, events, collections all derive from this instead of counting events |
| Event-keyed journal: entries have stable ids and `record` returns only new ones | `Journal/JourneyJournal.swift` | Level-ups, quests, events, wildlife, shared discoveries, team world milestones |
| Deterministic per-day randomness (FNV hash of day + index, used for chest positions) | `WalletState.chestMeters` | World events, wildlife sightings, companion finds: same result however often the app recalculates, so closing/reopening can't re-roll |
| Per-data-source storage (Health vs Demo) for progression, wallet, journal, companion | `LocalStore` | Quests, XP, collections, titles: demo stays isolated automatically |
| Wallet with idempotent payouts and "opened ids" sets | `Shop/WalletState.swift` | Quest/event reward claiming |
| Rarity + weighted rolls, 30 cosmetics, slot-based outfit overlays | `ShopCatalog`, `EquipmentArt` | Exclusive/quest/event/premium cosmetics, companion accessories |
| Procedural biome painter with parallax layers, deterministic per biome | `PixelArt/SceneRenderer`, `BiomeScenes`, `FarSideScenes` | Seasonal pass, event overlays, team-world biomes |
| Companion growth (5 stages + per-km details + elder glow) | `Companions/`, `CompanionSprites` | Personalities, accessories, reactions |
| Teams: membership, invites, weekly standings, expeditions, badges | `Teams/Teams.swift`, migration `20261028…` | Campfire, team worlds |
| Notification ledger and game notifications | `Notifications/GameNotifications.swift` | Quest complete, event spotted, level up, team world unlocks |
| `TeamWeek.start` (Monday), `LocalDay` | Domain utilities | Daily/weekly resets |

### Partially existing features
- **Collections:** 20 relics exist (one per zone) and the World tab shows them. No categories, wildlife, postcards or memories.
- **Companion details:** per-km details and elder glow exist; no personalities in gameplay, reactions, idle variety or accessories.
- **Team progression:** expeditions and weekly badges exist, but are **computed live** (see issue A).
- **Titles/profile:** username + walker only.
- **Events:** none; the closest is the deterministic daily chests.

### Compatibility issues found (must be fixed or designed around)

**A. Team distance goes backwards when someone leaves.** `my_team()` sums the
*current* members' distance since they joined. If a member leaves, the team
total, expedition progress and earned expedition badges drop. Team worlds and
the campfire need a **persistent contribution ledger** instead (Phase 6). This
also fixes the existing expeditions.

**B. Coins, items, quests and XP live only on the phone.** "Restoring accounts
on a new device" needs a **cloud save** (Phase 0). Today a new phone starts
from 50 coins.

**C. Walking totals are client-reported.** The server caps a day at 150 km but
can't verify it. Server-side validation therefore means: rewards derive from
the *uploaded* daily totals with caps, each reward id is unique in the
database, and shared rewards (teams, shared discoveries) are granted by
server functions, never by the client.

**D. Team-switch farming.** With the current rule, a day walked before joining
(`joined_at - 1`) counts for the new team. With a ledger, each
`(user, local_date)` can be credited to **one team only**, forever.

**E. Midnight and time zones.** Days are local (`LocalDay` in the current time
zone). Travelling can repeat or skip a day; every reward id therefore includes
the ISO day (`quest-2026-10-30-steps2000`), so a repeated day can't pay twice.
Weekly ids use the Monday date.

**F. Art cache growth.** Seasonal variants multiply scene renders (20 biomes ×
4 seasons). The cache key gains a season; only the current season is rendered.

**G. Demo mode.** Everything new is stored per data source, like the wallet.
Server-side features (teams, shared discoveries, team worlds) already ignore
demo walking, because demo progress is never uploaded.

## 2. Design decisions

1. **Derive, don't accumulate.** XP, collection status and quest progress are
   computed from permanent facts (lifetime best-per-day distances, discovered
   ids, claimed reward ids). A refresh can only move them forward, and there is
   no running counter to double.
2. **One reward ledger.** Every grant (quest, event, level, collection, team
   world) has a stable id. `RewardLedger.claim(id)` pays once; the ledger is part
   of the cloud save, and the server keeps its own unique ids for shared grants.
3. **Deterministic events.** A day's world events are picked by hashing
   `(event pool version, local day, zone)`. Everyone sees the same events on the
   same day, which is what makes **shared discoveries** possible: if two
   friends both reach Cloud Forest on a "forest spirit" day, both found it.
4. **Configurable content.** Quests, events, seasons, wildlife, titles,
   worlds and campfire levels are data tables in `WalkscapeDomain` (like
   `ZoneCatalog`). Shared progression thresholds (team worlds, community goals)
   also live in Supabase tables so they can be tuned without an app update.
5. **No new grind.** Daily quests stay at or under 1–2 km; weekly quests at or
   under 15 km; no reward needs more than an ordinary walk.
6. **Missed events come back.** Seasonal events recur every year, and their
   cosmetics enter the regular Mystery Box pool after their first run.

## 3. Phases

Each phase ends with green CI and a TestFlight build, so nothing big lands
untested. Sizes: S ≈ a day of work, M ≈ 2–3, L ≈ 4–6.

### Phase 0 — Foundations: reward ledger, Explorer XP, cloud save (M)
- `Progression/ExplorerLevel.swift`: XP formula and levels. XP =
  100/km lifetime (from `dailyBestMeters`, capped at 25 km/day) + 50/zone
  discovered + 75/relic + 100/achievement + quest/event XP from the ledger.
  Level n needs `100 · n^1.5` XP more than level n−1 (level 2 ≈ 1 km, level 10
  ≈ 3 weeks of normal walking, level 30 ≈ a year).
- `RewardLedger`: claimed ids, coins/items/XP granted, Codable, per source.
- Level-up banner + Journal entries; level and XP bar on Profile and Journey.
- Cloud save: `player_saves` table (one JSON row per user, RLS owner-only,
  version + `updated_at`), merged by union of ids and max of counters, so two
  phones never lose rewards. Upload after each change; download on sign-in.
- DB tests: owner-only access, merge never loses ids, deleted with account.

### Phase 1 — Daily, weekly and companion quests (M)
- `Quests/`: `QuestDefinition` (goal kind: steps, metres, chests opened, coins
  earned, zone discovered, walked-with-friend, active days, expedition done,
  companion km), `QuestBoard` picks 3 daily + 4 weekly + 1 companion quest
  deterministically from the day/week, so the board is identical after a relaunch.
- Progress derives from daily totals and ledger facts; "walk with a friend" uses
  today's friend summaries.
- Claim buttons; claimed ids in the ledger; weekly completion chest.
- UI: a **Quests** card on Journey (today's 3) opening a Quests sheet
  (daily / weekly / companion tabs, reset countdowns).
- Tests: midnight and Monday resets, repeated days, refreshes, demo isolation,
  rewards once.

### Phase 2 — Titles and profile customization (S–M)
- `Profile/Titles.swift`: about 20 titles unlocked by achievements, levels,
  collections, events and team worlds (The Wanderer, Forest Guardian, Lighthouse
  Keeper, The Collector, Eternal Rambler…).
- Profile: choose a title, favourite-zone background (existing scene renderer),
  showcased companion, 3 showcased achievements, frame (unlocked by level/Plus).
- Server: `profiles.title_id`, `frame_id`, `favorite_zone_id`, validated
  against an allowed-id list; shown under usernames in Friends, Team and the
  friend day card.

### Phase 3 — Collections: wildlife, postcards, treasures, memories (L)
- `Collections/`: five categories; relics stay as they are.
- **Wildlife:** 24 original creatures (Meadow Rabbit, River Otter, Forest Owl,
  Crystal Wisp, Snow Fox, Firefly Sprite, Mountain Goat, Moonlit Deer…), each with
  rarity, zones, personality, sighting rules (zone reached + deterministic daily
  chance by rarity; rare ones also via events), and procedural pixel sprites.
- **Postcards:** scene snapshots of special moments (first Summit, first
  sunrise walk, events); rendered with the existing scene painter and shareable.
- **Treasures:** rare event/quest finds. **Memories:** personal milestones
  (first 10 km day, 100 km lifetime, companion elder…), built from the Journal.
- **Collection screen** from the World tab: grid per category, filters (rarity,
  zone), detail cards with discovery dates, completion percentages, and
  collection achievements plus rewards.

### Phase 4 — Living world: events, seasons, companion personalities (L)
- `Events/WorldEvents.swift`: event pool (shooting star in Starlight Pass,
  travelling merchant in Hearth Village, fireflies in Firefly Marsh, rainbow,
  footprints in Pine Forest, forest spirit in Cloud Forest, treasure chest in an
  explored zone…) with zone links, rarity, time windows (evening only, a
  weekend…) and rewards. Rolled deterministically per day: at most 1–2 a day,
  claimed once by id, recorded in the Journal.
- `PixelArt/Seasons.swift`: one reusable seasonal pass over any biome:
  palette shift (winter cold/desaturated, autumn orange, spring pastel, summer
  bright) plus overlay layers (snow cover and frozen water, blossoms and
  butterflies, fireflies, falling leaves and harvest props). Northern-hemisphere
  meteorological calendar (Dec–Feb winter…), with a flip option for the southern
  hemisphere. No change to zone progression.
- Event and season sprites drawn on the scene; the merchant opens a small
  limited stock of items.
- **Companions:** personality finds (Mossling: minerals and stones; Emberfox:
  coins and treasure; Moonmoth: flowers and night wildlife) using a deterministic
  daily chance; reactions on zone entry and milestones; 3–4 idle animations per
  species; **companion accessories** (hat, scarf, backpack) as a new equipment
  target in the shop.

### Phase 5 — Social: shared discoveries, milestones, reactions (M)
- Server `discoveries` table (user, discovery id, local day), written by a
  function from the client's claims. A daily job (or on read) finds friends who
  found the same special discovery on the same day and creates a
  `shared_discoveries` row once per pair, so both get a Journal entry and a bonus.
- Friend milestones (first 10 km, 50 km, companion evolution, first expedition,
  100 km walked together) as feed items on the Friends tab.
- Reactions: 👏 🎉 🔥 style pixel stickers, one per milestone per friend,
  RLS-limited to friends, optional push.

### Phase 6 — Team ledger and the Campfire (M)
- **Fixes issue A:** `team_contributions (team_id, user_id, local_date, meters)`
  with **unique (user_id, local_date)**, filled by a server function from
  uploaded daily totals for days *after* joining (cap 25 km/day per member).
  Leaving keeps past contributions with the team; a new team only gets future
  days. Expeditions switch to the ledger total, so they never go backwards.
- **Campfire:** 5 levels (campfire → tent and lantern → benches → camp village →
  expedition HQ), from the team's cumulative ledger distance plus expedition
  completions. Decorations unlock along the way, and members place a few from the
  team's unlocked set (`team_campsite` row: level, placed decorations). Drawn
  procedurally, shown at the top of the Team view, identical for every member.
- Personal rewards for reaching campfire levels go into each member's ledger by
  id (`campfire-<team>-3`), so leaving and rejoining can't repeat them.

### Phase 7 — Team worlds (L+, the biggest phase)
- Unlocked once a team completes Summit Relay (75 km), configurable.
- `TeamWorlds/`: world catalog: The Enchanted Forest, Crystal Kingdom, Forgotten
  Desert, Floating Isles, Ancient Kingdom. Each has 5–6 zones with new biomes,
  relics, wildlife, treasures, world quests and a final community challenge
  (e.g. "Wake the Ancient Tree: 60 km in 7 days as a team").
- Thresholds in a Supabase table (`team_world_zones`: world, zone, cumulative
  metres, e.g. 100 km, +150 km…) mirrored in the app for offline display.
- Progress = the team's ledger distance since unlocking; a server function
  advances the team's world position and writes unlock rows once
  (`team_world_unlocks`, unique per team + zone).
- Member rewards: each member present at the unlock gets the zone's relic and
  rewards once **per person** (unique per user + zone, across all teams), so
  switching teams can't farm the same zone twice; past rewards stay after leaving.
- UI: a **world map** of connected zones (pixel paths, team marker, fog over
  locked zones), unlock animation, contribution list (each member's km this
  world), and the current zone's scene with the team's walkers.
- New biome painters (enchanted forest, crystal palace, desert ruins, sky
  islands, ancient city), reusing the painter primitives.

### Phase 8 — Seasonal events framework (M)
- `SeasonalEvent` config: id, dates (recurring yearly), quests, exclusive
  cosmetics, limited discoveries, optional **community goal** (all players'
  combined km, computed by a server function over `daily_progress`), and
  progression tiers.
- First events: Great Harvest (autumn), Winter Wanderer, Starfall Festival,
  Spring Awakening, Ocean Expedition (community challenge).
- Event banner with dates and progress on Journey; event tab in Quests. Event
  items join the Mystery Box pool after their first year.

### Phase 9 — Cosmetic store and Walkscape Plus with StoreKit 2 (L)
- Non-consumable bundles (seasonal outfits, companion skins, trail effects,
  walker animations, campsite decorations) and an optional **Walkscape Plus**
  subscription (exclusive cosmetic collections, premium frames, Journal themes,
  campsite decorations, seasonal collections). No ad removal; core gameplay free.
- StoreKit 2 in the app (product list, purchase, restore,
  `Transaction.updates`); entitlements derived from verified transactions.
- Server validation: an Edge Function verifies Apple's signed transactions and
  App Store Server Notifications and writes an `entitlements` table, so
  premium cosmetics follow the account to a new phone.
- **Needs you first:** Paid Applications agreement, banking and tax in App Store
  Connect, product ids and prices, subscription group, and an App Store Server
  API key. Sandbox testers for TestFlight testing.

## 4. Order and dependencies

```
Phase 0 ─┬─ 1 Quests ─────────────┐
         ├─ 2 Titles ──────────────┤
         ├─ 3 Collections ── 4 Living world ── 5 Social
         └─ 6 Team ledger + Campfire ── 7 Team worlds
                                           8 Seasonal events (needs 1, 3, 4)
                                           9 Store (needs 0; cosmetics from 2–8)
```

Suggested release grouping for TestFlight:
- Build 7: Phases 0–1 (XP, cloud save, quests) + the friend day card and notifications.
- Build 8: Phases 2–3 (titles, collections).
- Build 9: Phase 4 (events, seasons, companions).
- Build 10: Phases 5–6 (social, campfire, ledger fix).
- Builds 11–12: Phase 7 (team worlds).
- Build 13: Phase 8; Phase 9 once the App Store Connect setup is done.

## 5. Testing approach
- Every rule in `WalkscapeDomain` gets unit tests: resets at midnight and Monday,
  repeated or skipped days (travel), HealthKit revisions downward, refresh
  repeats, ledger uniqueness, demo isolation, level boundaries, deterministic
  rolls.
- Every new table and function gets database tests in `supabase/tests`: RLS,
  unique grants, team switching and leaving, account deletion cascades.
- The existing tests run unchanged before and after each phase; CI must stay green.
- `pixel-preview` gains seasonal, wildlife, campfire and world renders, so art
  is reviewable from the CI artifact without a Mac.

## 6. Risks and open points
- **Phase 7 size:** five worlds of new art is the largest single piece. I'd ship
  World 1 fully, then add the others as content updates (the system supports it).
- **Server cost:** shared discoveries and community goals run aggregate queries;
  they use indexed daily tables and are computed on read with caching.
- **Client-reported distance** stays the trust boundary (issue C); per-day caps
  limit damage in shared progression.
- **App Store review:** subscriptions need clear terms and restore; loot-style
  mechanics must keep the published odds (the Mystery Box already shows them).
