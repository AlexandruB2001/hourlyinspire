# Privacy

## What Walkscape reads

- Apple Health **step count** and **walking + running distance**, as daily
  totals from local midnight to now. Read-only; nothing is written to Health.

## What Walkscape does not do

- No GPS, no Core Location, no location permission, no maps, and no nearby or
  proximity features. The friend track compares *distance walked*, never
  *where* anyone is.
- No raw Health samples leave the device.

## What friends can see

- Your username, avatar, and today's step and distance totals, with the time
  they were last updated.
- Only friends whose request you accepted. You can remove or block a friend at
  any time, and turn off sharing in Profile.

## Stored on device

- Settings (username, avatar, data source, toggles).
- Per-day best distance, discovered zones and collected items. This is what
  the lifetime total and achievements are computed from.
- Demo-mode progress, kept separately from Apple Health progress.
- Coins, shop items you own and your current outfit. Coins are earned only by
  walking; there are no real-money purchases.

## Server (when signed in)

- Sign in with Apple, requesting **no** name or e-mail scope.
- Stored: username, walker, sharing preference, friendships and blocks, and
  one row of daily totals per day (only while sharing is on, and never from
  demo mode).
- Row level security limits each table to its owner, and limits daily totals
  to accepted friends while sharing is on. Tested in `supabase/tests`.
- **Delete account** (Profile → Account) removes the server account and all of
  the above immediately.
- See [`BACKEND.md`](BACKEND.md) for the limits of client-reported totals.
