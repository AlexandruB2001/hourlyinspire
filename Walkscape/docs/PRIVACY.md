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
- Coins, shop items you own and your current outfit. Coins are earned by
  walking, referral chests and rewarded ads; there are no real-money purchases.
- Ad limits: first launch date, when the last app-open ad was shown and how
  many rewarded ads were watched today.
- Notification choices, and which events were already announced (so none
  repeats).

## Ads

- Ads are served by **Google AdMob** (Google Mobile Ads SDK). The SDK collects
  device and usage data such as the IDFA (only if you allow tracking), IP
  address, coarse location derived from IP, and ad interactions, as described
  in Google's own privacy manifest and policies.
- Walkscape never passes Health data, walks, usernames or friends to the ad SDK.
- iOS asks before any tracking (App Tracking Transparency). In the EEA and UK,
  Google's consent form is shown first, and **Profile → Ad privacy choices**
  lets you change your answer.
- Consent prompts only appear after you've picked a companion.
- Debug, simulator and TestFlight builds always show Google test ads.

### App Store privacy label (update before App Store release)

With AdMob, the label needs: Identifiers → Device ID, Usage Data → Advertising
Data and Product Interaction, Location → Coarse Location, and Diagnostics,
marked as used for Third-Party Advertising and, for Device ID, Tracking.
See Google's "Prepare for Apple's App Store data disclosure requirements".

## Notifications

- Off until you turn them on in Profile, and only after iOS asks you.
- Chests, zones, relics, achievements, companion growth, referral chests and
  the daily reminder are created on your phone; nothing is sent anywhere.
- Friend requests and team invites are pushed by the Walkscape server. For
  that, your phone's push token is stored with your account. It is never
  visible to other players, is removed when you sign out, and is deleted with
  your account. A push contains only a username and team name.
- Each kind can be switched off separately in Profile.

## Server (when signed in)

- Sign in with Apple, requesting **no** name or e-mail scope.
- Stored: username, walker, sharing preference, friendships and blocks, and
  one row of daily totals per day (only while sharing is on, and never from
  demo mode).
- Row level security limits each table to its owner, and limits daily totals
  to accepted friends while sharing is on. Tested in `supabase/tests`.
- A cloud save of your Apple Health game progress (discoveries, best distance
  per day, coins, items, journal, rewards and companion), so a new phone can
  restore it. Only you can read it.
- **Delete account** (Profile → Account) removes the server account and all of
  the above immediately.
- See [`BACKEND.md`](BACKEND.md) for the limits of client-reported totals.
