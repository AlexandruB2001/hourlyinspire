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

TESTFLIGHT (done 2026-10-27)
- App Store name "Walkscape Journey" ("Walkscape" was taken; the home-screen name
  is still Walkscape). App Store Connect app id 6827387213.
- App ID com.alexandrub.walkscape registered with HealthKit + Sign in with Apple.
- API key "GitHub Walkscape" (Admin), Key ID 63G6GMN9G2. GitHub secrets
  APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY are set.
- main has a copy of walkscape-testflight.yml only so "Run workflow" exists
  (workflow_dispatch needs the default branch). Run it with this branch selected;
  runs use this branch's version. Remove it from main when Walkscape moves repos.
- TestFlight internal group "Internal Testers" has automatic distribution on.

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
