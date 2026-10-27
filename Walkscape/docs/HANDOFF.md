WALKSCAPE — HANDOFF NOTES (paste this into a new Claude session to continue)
===========================================================================

PROJECT
- Walkscape: cozy pixel-art walking game for iPhone (SwiftUI + HealthKit + Supabase).
- Code: GitHub repo AlexandruB2001/hourlyinspire, branch claude/walkscape-ios-game-5jpoy4,
  folder Walkscape/. (The repo also holds the separate HourlyInspire pages on main;
  don't touch those. Walkscape should move to its own repo eventually.)
- Bundle ID: com.alexandrub.walkscape
- Developer is on Windows: no Mac. All iOS builds happen in GitHub Actions on macOS.
- Read Walkscape/README.md, Walkscape/CLAUDE.md and Walkscape/docs/CHECKLIST.md first.

DONE
- Milestones 1–3: Journey, Friends track, World and Profile screens; pixel art;
  HealthKit service; zone progression; friend track with edge indicators and
  "Back to me".
- Milestone 4 (backend):
  - Supabase schema with row level security, plus 64 database tests.
  - Swift client (Sign in with Apple, friends, progress sync), 81 package tests.
  - App wiring: sign in/out, account deletion, sharing daily totals.
- Supabase project "walkscape" (ref tsajekigvuwoeqdfwnib, region us-west-2) is
  live:
  - schema applied and verified;
  - Sign in with Apple enabled for com.alexandrub.walkscape;
  - email sign-up disabled;
  - publishable key in Walkscape/Config/Base.xcconfig.
  Details: Walkscape/docs/BACKEND.md
- CI (.github/workflows/walkscape.yml) on every push:
  - Linux package tests and database tests;
  - iOS simulator build with the newest Xcode.
  Last run: all green.
- TestFlight workflow written (.github/workflows/walkscape-testflight.yml) and
  a privacy manifest added. The workflow has NOT run yet.

WHERE WE STOPPED: TestFlight setup (needs my Apple login)
See Walkscape/docs/TESTFLIGHT.md. Remaining steps:
[ ] 1. App Store Connect → Users and Access → Integrations → App Store Connect API
       → Team Keys → +. Name "GitHub Walkscape", access Admin. Download the .p8
       (one chance only). Note the Key ID and Issuer ID.
[ ] 2. Team ID: developer.apple.com/account → Membership details.
[ ] 3. GitHub repo → Settings → Secrets and variables → Actions → add:
       APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (full .p8 text,
       including the BEGIN/END lines). Never paste these into a chat.
[ ] 4. If com.alexandrub.walkscape isn't registered yet:
       developer.apple.com → Identifiers → + → App ID, with the HealthKit and
       Sign in with Apple capabilities. (Or let the first workflow run register it.)
[ ] 5. App Store Connect → Apps → + → New App: iOS, name "Walkscape",
       bundle ID com.alexandrub.walkscape, SKU walkscape.
[ ] 6. Run GitHub → Actions → "Walkscape TestFlight" → Run workflow. Wait about
       15 minutes for processing, then TestFlight → Internal Testing → add
       myself → install on my iPhone.

AFTER TESTFLIGHT (next work)
- Test on iPhone:
  - Health permission flow;
  - Sign in with Apple;
  - two accounts adding each other as friends;
  - progress sync;
  - offline and stale states.
- Fix whatever the device testing finds.
- Sync discoveries/achievements to the server (tables already exist).
- Notifications (the reminder toggle is stored but does nothing yet).
- Move Walkscape into its own GitHub repo.

SECURITY NOTES
- The Supabase access token used for setup was deleted. If Claude needs Supabase
  access again, create a new token, then revoke it afterwards.
- The Supabase database password is in my password manager. It is NOT in the
  repo or in this file.
- Only the Supabase publishable key ships in the app. Never commit the
  service_role / secret key.

MESSAGE TO PASTE INTO THE NEW SESSION
"I'm continuing Walkscape (repo AlexandruB2001/hourlyinspire, branch
claude/walkscape-ios-game-5jpoy4). Read Walkscape/docs/HANDOFF.md. I'm at the
TestFlight setup step: [say which steps are done]."
