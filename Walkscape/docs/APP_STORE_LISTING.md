# App Store listing (version 1.0.0)

Paste these into App Store Connect, under App Store → iOS App → 1.0 Prepare for Submission, and App Information.
Character limits are Apple's; the counts here were checked.

## App Information

| Field | Value |
|---|---|
| Name (30) | Walkscape Journey |
| Subtitle (30) | Your steps grow a pixel world |
| Primary category | Games → Casual |
| Secondary category | Health & Fitness |
| Privacy Policy URL | https://alexandrub2001.github.io/privacy.html |
| Support URL | https://alexandrub2001.github.io/support.html |
| Marketing URL | https://alexandrub2001.github.io |
| Copyright | 2026 Alexandru Busuioc |

## Promotional text (170, can change anytime without review)

> Walk anywhere, and your little explorer walks too. A new place every kilometre, two chests along the way, and a companion that grows up with every step.

## Description (4000)

> Walkscape turns your everyday steps into a cozy pixel-art adventure.
>
> Every step you take moves your little explorer across a hand-drawn world. Walk to the shop, take the dog out, wander the long way home: it all counts. Walkscape reads your steps and walking distance from Apple Health, so you don't even need the app open while you walk.
>
> A NEW PLACE EVERY KILOMETRE
> Follow one long trail through meadows, riversides, pine forests, snowy ridges, firefly marshes and more, all the way to the lighthouse on the coast. Every kilometre takes you somewhere new.
>
> CHESTS ON THE TRAIL
> Two chests appear for every kilometre you walk. Open them for coins, then spend your coins on Mystery Boxes full of outfits: hoodies, crowns, wizard hats, halos, wings and rare glowing trails.
>
> A COMPANION THAT GROWS WITH YOU
> Choose an Emberfox, a Mossling or a Moonmoth. Your companion walks beside you and grows up as you go, from Hatchling to Elder at 100 km. Dress them up with capes, scarves, hats and more.
>
> WALK WITH FRIENDS
> Add friends and see everyone on one shared trail, placed by how far they've walked today. Climb the daily leaderboard, or start a team with one code and walk together to unlock team worlds.
>
> SO MUCH TO COLLECT
> Spot wildlife, find treasures, unlock achievements, earn titles and profile frames, and level up your Explorer all the way to level 100. Seasonal festivals bring limited-time rewards.
>
> ON YOUR HOME SCREEN AND WRIST
> Home Screen widgets show today's distance and your walker. The Apple Watch app and watch face complications let you check your walk without your phone.
>
> PRIVATE BY DESIGN
> No GPS and no location tracking, ever. Walkscape only reads daily step and distance totals from Apple Health, and friends see your distance, never where you are.
>
> Walkscape is free to play. It's supported by optional ads, which you choose to watch for bonus coins.
>
> No pressure, no streaks to lose. Just walk, and watch your world grow.

If the store and Walkscape Plus are on at launch, add before the last line:
> Optional Walkscape Plus adds extra outfits, decorations and a second free Daily Chest each day, and cosmetic bundles add more looks. Nothing in the game is locked behind a purchase.

## Keywords (100, comma-separated, no spaces)

```
walking,steps,pedometer,step counter,cozy,pixel,walk,fitness,companion,pet,adventure,idle,health
```
(96 characters. Don't repeat words from the name or subtitle; Apple already indexes those.)

## What's New (first release)

> Welcome to Walkscape! Your first steps start the journey.

## App Review notes

> Walkscape reads step count and walking distance from Apple Health (read-only). To try it without Health data, open Profile and set the data Source to "Demo data", or tap "Use demo data" on the Journey screen.
> Friends, teams and the daily leaderboard need Sign in with Apple (no name or email is requested).
> Ads are Google AdMob; rewarded ads are optional and give bonus coins.

Sign-in: Sign in with Apple only, so no demo account is required. Leave "Sign-in required" unticked.

## Age rating (questionnaire suggestions)

- Violence (cartoon or realistic), sexual content, profanity, horror, drugs, gambling with real money: **None**.
- Simulated gambling: **None**. The Mystery Box is bought only with coins earned by walking (coins aren't sold), its odds are shown in the app, and it never pays out anything with real-world value. If Apple disagrees in review, change this to "Infrequent/Mild".
- Unrestricted web access: **No**.
- User-generated content: usernames only, with block and report. Answer **No** to chat and messaging.
- Contests: **No**.
- Expected rating: **4+** (9+ if Apple flags the Mystery Box).

## App Privacy (nutrition label)

From docs/PRIVACY.md and Google's AdMob disclosure:

| Data type | Linked to user | Used for tracking | Purpose |
|---|---|---|---|
| Health & Fitness → Fitness (daily steps/distance totals, when signed in and sharing) | Yes | No | App Functionality |
| User ID (account id) | Yes | No | App Functionality |
| Other User Content → username | Yes | No | App Functionality |
| Purchases (App Store transactions, if the store is on) | Yes | No | App Functionality |
| Identifiers → Device ID (IDFA, AdMob, only with tracking permission) | No | Yes | Third-Party Advertising |
| Usage Data → Advertising Data, Product Interaction (AdMob) | No | Yes (Advertising Data) | Third-Party Advertising, Analytics |
| Location → Coarse Location (AdMob, from IP) | No | No | Third-Party Advertising |
| Diagnostics → Crash/Performance (AdMob SDK) | No | No | Third-Party Advertising |

Not collected: precise location, contacts, email, name, browsing history, financial info.
The app asks permission before tracking (App Tracking Transparency).

## Screenshots

6.9-inch iPhone (1320 × 2868), up to 10. They're made by `walkscape_social/store_screens/make_store_screens.py` in the social folder from real iPhone screenshots, with a caption on each. Order:

1. Journey: the walker and companion on the trail ("Your steps move a tiny world")
2. Distance and chests ("A new place every kilometre")
3. Companions ("A companion that grows with you")
4. Shop or Mystery Box outfits ("Collect outfits for your walker")
5. Social trail or leaderboard ("Walk with your friends")
6. World map or collections ("Wildlife, treasures and achievements")
7. Widget or Apple Watch ("On your Home Screen and wrist")
