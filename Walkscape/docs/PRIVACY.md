# Privacy

## What Walkscape reads

- Apple Health **step count** and **walking + running distance**, as daily
  totals from local midnight to now. Read-only; nothing is written to Health.

## What Walkscape does not do

- No GPS, no Core Location, no location permission, no maps, and no nearby or
  proximity features. The friend track compares *distance walked*, never
  *where* anyone is.
- No raw Health samples leave the device.

## What friends can see (once sync exists)

- Your username, avatar, and today's step and distance totals, with the time
  they were last updated.
- Only friends whose request you accepted. You can remove or block a friend at
  any time, and turn off sharing in Profile.

## Stored on device

- Settings (username, avatar, data source, toggles).
- Per-day best distance, discovered zones and collected items. This is what
  the lifetime total and achievements are computed from.
- Demo-mode progress, kept separately from Apple Health progress.

## Backend (Milestone 4, planned)

Only daily aggregates will be synced. Row-level security will limit friends to
permitted daily summaries. Client-submitted totals can't be fully verified, so
the server will apply plausibility limits (for example a maximum daily
distance) and the limitation will be documented.
