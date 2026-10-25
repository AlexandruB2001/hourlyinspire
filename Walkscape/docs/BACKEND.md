# Backend (Supabase)

Walkscape uses Supabase for accounts, friendships and sharing daily totals.
Without configuration the app runs in **local-only mode** with sample friends.

| Piece | Where |
|---|---|
| Schema, RLS, API functions | `supabase/migrations/*.sql` |
| Database tests (64 checks) | `supabase/tests/` (`run.sh`) |
| Swift client | `Packages/WalkscapeKit/Sources/WalkscapeBackend` |
| App wiring | `Walkscape/App/AppModel.swift` (Account section), `Walkscape/Data/Backend/` |

## Setting it up (all in the browser)

### 1. Create the project

1. Sign in at <https://supabase.com> and create a project (the free tier is fine).
2. Pick a strong database password and store it in a password manager.

### 2. Create the tables

1. Dashboard → **SQL Editor** → *New query*. The quickest way: paste all of
   `supabase/setup.sql` (both migrations in one file) and click **Run**. Or run
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
