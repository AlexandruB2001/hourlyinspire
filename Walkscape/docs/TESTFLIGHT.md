# TestFlight

`.github/workflows/walkscape-testflight.yml` archives a signed Release build
and uploads it to App Store Connect. Signing is automatic: Xcode uses an App
Store Connect API key to register the App ID (with HealthKit and Sign in with
Apple), and to create the certificate and provisioning profile. No Mac is needed.

## One-time setup (Apple account holder)

### 1. Create an App Store Connect API key
1. <https://appstoreconnect.apple.com> → **Users and Access** → **Integrations**
   → **App Store Connect API** → **Team Keys** → **+**.
2. Name: `GitHub Walkscape`. Access: **Admin**. Automatic signing needs to
   create certificates, and lower roles can't.
3. **Download** the `.p8` file. Apple only lets you download it once.
4. Note the **Key ID** (in the list) and the **Issuer ID** (above the list).

### 2. Find your Team ID
<https://developer.apple.com/account> → **Membership details** → **Team ID**.

### 3. Add four GitHub secrets
GitHub → repository → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID |
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY` | The whole `.p8` file, opened in Notepad, including the `-----BEGIN/END PRIVATE KEY-----` lines |

### 4. Run the workflow once (registers the App ID)
GitHub → **Actions** → **Walkscape TestFlight** → **Run workflow**. On the first
run, signing registers `com.alexandrub.walkscape`. The upload step then fails
with a "no app record" error until step 5 is done. That's expected.

### 5. Create the app record
App Store Connect → **Apps** → **+** → **New App**:
- Platform: iOS. Name: Walkscape (any free name). Language: English.
- Bundle ID: `com.alexandrub.walkscape`. SKU: `walkscape`. Access: Full.

### 6. Run the workflow again
The build appears under **TestFlight** after Apple processes it (5–15 min).
Add yourself under **Internal Testing**, then install from the TestFlight app
on your iPhone.

## Each new build
Run the workflow. The build number is the workflow run number, so it always
increases. The version (`MARKETING_VERSION` in `project.yml`) is 0.1.0.

## Before external testers
Fill in **App Privacy** in App Store Connect to match `Resources/PrivacyInfo.xcprivacy`:
- Fitness: linked to the user, used for app functionality, not tracking.
- User ID: linked to the user, used for app functionality, not tracking.

Add a privacy policy URL as well.
