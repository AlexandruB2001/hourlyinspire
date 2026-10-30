# Backend (Supabase)

Walkscape uses Supabase for accounts, friendships and sharing daily totals.
Without configuration the app runs in **local-only mode** with sample friends.

| Piece | Where |
|---|---|
| Schema, RLS, API functions | `supabase/migrations/*.sql` |
| Database tests (64 checks) | `supabase/tests/` (`run.sh`) |
| Swift client | `Packages/WalkscapeKit/Sources/WalkscapeBackend` |
| App wiring | `Walkscape/App/AppModel.swift` (Account section), `Walkscape/Data/Backend/` |

## Current project

| | |
|---|---|
| Project | `walkscape` (ref `tsajekigvuwoeqdfwnib`, region us-west-2) |
| API | `https://tsajekigvuwoeqdfwnib.supabase.co` |
| Schema | `setup.sql` applied on 2026-10-25 via the Management API and verified (RLS on every table, 16 policies, seed data) |
| Auth | Sign in with Apple only (client ID `com.alexandrub.walkscape`, email optional); email/password sign-up disabled |
| App key | publishable key in `Config/Base.xcconfig` |

The migrations were applied by hand, not with the Supabase CLI, so the
project has no CLI migration history yet. Before using `supabase db push`,
mark them as applied with `supabase migration repair --status applied 20261025000001 20261025000002`.
Apply future schema changes as new files in `supabase/migrations/`.

## Setting it up from scratch (all in the browser)

### 1. Create the project

1. Sign in at <https://supabase.com> and create a project (the free tier is fine).
2. Pick a strong database password and store it in a password manager.

### 2. Create the tables

1. Dashboard → **SQL Editor** → *New query*. The quickest way: paste all of
   `supabase/setup.sql` (every migration in one file) and click **Run**. Or run
   them one at a time:
2. Paste all of `supabase/migrations/20261025000001_initial_schema.sql` and click **Run**.
3. Do the same with `supabase/migrations/20261025000002_seed_reference_data.sql`.

(With the Supabase CLI you can instead run `supabase link` then `supabase db push`
from the `Walkscape` folder.)

### 3. Enable Sign in with Apple

1. Dashboard → **Authentication** → **Sign In / Providers** → **Apple** → enable.
2. Under **Client IDs**, enter the app's bundle identifier (the
   `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`). Native iOS sign-in only needs
   this; the "Secret Key" fields are for web sign-in and can stay empty.
3. In the Apple Developer portal, the App ID needs the **Sign in with Apple**
   capability. Xcode's automatic signing adds it from the entitlements file.

### 4. Connect the app

Dashboard → **Project Settings** → **API**. Copy the project URL *host* (e.g.
`abcd1234.supabase.co`, without `https://`) and the **anon / publishable** key.

- **CI and TestFlight builds:** in GitHub → repo **Settings** → **Secrets and
  variables** → **Actions**, add `SUPABASE_HOST` and `SUPABASE_ANON_KEY`. The
  workflow writes them into `Config/Secrets.xcconfig` before building.
- **Local Xcode builds:** copy `Config/Secrets.example.xcconfig` to
  `Config/Secrets.xcconfig` (git-ignored) and fill it in.

Never use the `service_role` key in the app or in these secrets. It bypasses
row level security.

## Data model

| Table | Contents | Who can read | Who can write |
|---|---|---|---|
| `profiles` | username, avatar, share flag (no e-mail) | signed-in users, except across a block | owner (username, avatar, share flag only) |
| `friendships` | requester, addressee, `pending`/`accepted` | the two participants | requester inserts `pending`; acceptance only via function; either side deletes |
| `blocks` | blocker → blocked | blocker | blocker |
| `daily_progress` | one row per user per local date | owner; accepted friends while owner shares | owner |
| `zone_definitions`, `achievements` | reference data | signed-in users | nobody (migrations) |
| `user_discoveries`, `user_achievements` | permanent unlocks | owner | owner (insert only) |

## API functions

All client access goes through `POST /rest/v1/rpc/<function>`:

| Function | Purpose |
|---|---|
| `upsert_daily_progress` | Idempotent. Same values change nothing; an upload older than the stored one is ignored. |
| `friend_daily_summaries(date)` | Accepted friends with that day's totals (null when none or not shared). |
| `pending_friend_requests()` | Incoming and outgoing requests. |
| `send_friend_request(username)` | Rejects unknown users, yourself, duplicates and blocks (blocks look like unknown users). If they already asked you, this accepts. |
| `respond_to_friend_request(id, accept)` | Addressee only. |
| `delete_friend_request(id)` | Cancel an outgoing request or decline an incoming one. |
| `remove_friend(id)`, `block_user(id)`, `unblock_user(id)` | |
| `get_my_profile()`, `update_my_profile(...)` | Usernames are 3–20 of `a–z 0–9 _`, unique. |
| `delete_account()` | Deletes the auth user; everything else cascades. |

## Syncing

- Only **daily aggregates** are uploaded: date, time zone, steps, distance,
  distance source, and when they were read. Raw HealthKit samples never leave
  the phone.
- Uploads happen after each successful Apple Health refresh, including
  background deliveries, only while signed in and only while *Share daily
  totals* is on. **Demo data is never uploaded.**
- `DailyProgressSyncer` skips uploads identical to the last successful one.
  Failed uploads are retried on the next refresh.

## What the server can't guarantee

Totals come from the user's phone, so a determined user could submit fake
numbers. The database rejects only the implausible:

- steps and distance capped at 150,000 / 150 km per day;
- dates more than 7 days in the past or more than 1 day ahead (UTC) rejected;
- client timestamps more than 10 minutes in the future rejected.

Leaderboards are among friends who chose each other, which limits the
incentive to cheat. If public competition is added, this needs a stronger
design (e.g. server-side anomaly checks).

## Running the database tests

```sh
Walkscape/supabase/tests/run.sh            # needs Docker
DATABASE_URL=postgres://... run.sh         # or an empty Postgres 15+ database
```

The tests stub Supabase's `auth` schema and default grants on plain Postgres,
then check cross-user access, friendship rules, validation, idempotent sync,
blocking and account deletion. CI runs them on every push.

## Referrals and teams (migration 20261028000001)

What the server enforces (all tested in `supabase/tests/20_referrals_and_teams.sql`):

- **Codes**: every profile gets a unique 8-character `referral_code`. Codes are
  redeemed only through `redeem_referral_code`, only by accounts less than 14
  days old, once per account, never your own code, and never the code of
  someone you invited.
- **Qualification**: the invitee must walk 5 km on at least 2 different days
  within 30 days. This is computed in `ready_referral_chests` from the
  invitee's uploaded `daily_progress`, so they must be signed in with sharing on.
- **Reward**: the 25–100 coin amount is chosen once on the server when the
  referral qualifies and never changes; chests are marked opened with
  `mark_referral_chest_opened`. The app also keeps opened chest ids, so a chest
  is never paid twice even offline. At most 20 rewards per walker.
- **Deleted accounts**: the referral row is kept (with a null invitee), so
  deleting and re-creating an account doesn't earn a second chest for the
  same referral.
- **Teams**: one team per walker, at most 12 members, joined by code or by a
  friend's invite. Teammates see each other's day/week distance only while
  sharing is on; other teams see only names, sizes and combined distance.

Known limits (be honest about these):

- Walking totals are client-reported (see above), so a determined cheater can
  fake qualification. Plausibility limits on `daily_progress` still apply.
- Duplicate *people* are only detected per account. Someone with several Apple
  IDs can create several accounts. Stronger options: compare
  `auth.identities.provider_id` in `redeem_referral_code`, or add Apple
  DeviceCheck on the client.
- Coins and owned items live on the device (per data source); they are not
  synced to the server yet.

### Applying it to the live project

Applied to the live project on 2026-10-28 through the SQL Editor, together
with `20261027000001_far_side_zones.sql`, and verified (20 zones, 12
achievements, a referral code on every profile, 20 RLS policies). Before using
`supabase db push`, also mark these two as applied with `supabase migration repair`.

## Push notifications (migration 20261030000001, not live yet)

Game events (chests, zones, relics, achievements, companion growth, referral
chests, the daily reminder) are **local** notifications: the app posts them
itself after a background HealthKit refresh, so they need no server.

Friend requests and team invites are **pushed** by the server so they arrive
with the app closed:

1. The app registers its APNs token with `register_push_token(token,
   environment, social)` after the player allows notifications and is signed
   in. `unregister_push_token` runs on sign-out. Tokens are never readable by
   clients; deleting an account deletes its tokens.
2. Two Database Webhooks (INSERT on `friendships` and on `team_invites`) call
   the `send-push` Edge Function (`supabase/functions/send-push/index.ts`).
3. The function looks up the recipient's tokens (only those with `social`
   on) and sends an alert through APNs, deleting tokens Apple reports as gone.

If the app also sees the request during a background refresh, it does not
post a second, local copy while a push token is registered.

To switch it on:

1. Apple Developer → Keys → **+** → enable *Apple Push Notifications service
   (APNs)* → download the `.p8` (only once).
2. Run `20261030000001_push_notifications.sql` in the SQL Editor.
3. Edge Functions → *Deploy a new function* → name `send-push`, paste
   `index.ts`, turn **off** "Verify JWT" (webhooks authenticate with the secret).
4. Edge Functions → Secrets: `WEBHOOK_SECRET` (random), `APNS_KEY_ID`,
   `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (the .p8 contents), `APNS_TOPIC`
   (`com.alexandrub.walkscape`).
5. Database → Webhooks → two webhooks (INSERT on `public.friendships` and on
   `public.team_invites`) → *Supabase Edge Functions* → `send-push`, with the
   HTTP header `x-webhook-secret: <WEBHOOK_SECRET>`.
6. The app's entitlements already ask for push (`aps-environment`); automatic
   signing adds the capability to the App ID on the next TestFlight build.

## Cloud save (migration 20261031000001, not live yet)

`player_saves` holds one private JSON row per player: the Apple Health
progression, wallet, journal, reward ledger and companion (`CloudSave` in
WalkscapeDomain). Demo data is never uploaded.

- `get_player_save()` returns the caller's save and its version.
- `put_player_save(save, base_version)` stores it only if `base_version` is
  the version last read (0 for the first save); otherwise `save_conflict`.
- The app always fetches, merges and then stores (`CloudSaveService.sync`),
  retrying on a conflict, so two phones never overwrite each other's progress.
- Merge rules never lose anything: discoveries and owned items are unioned,
  the best distance per day is kept, coins = the larger lifetime earnings minus
  the larger lifetime spending, journal and reward ids are unioned.
- A phone whose progress was already saved to a different account doesn't mix
  it into a new one (`cloudSaveOwner` in LocalStore). Deleting an account
  deletes its save and frees the phone's progress for the next account.

Limits: the save is written by the app, so (like walking totals) it can't be
verified by the server. Shared rewards are always granted server-side.
