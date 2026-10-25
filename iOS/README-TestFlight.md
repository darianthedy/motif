# Building & installing the iOS app without a Mac

The native app builds on a **GitHub-hosted macOS runner**, is signed with
fastlane match, and is uploaded to **TestFlight**. You install it on your
iPhone from the **TestFlight** app. Everything here is done from the browser.

```
PR            →  ios-ci (macOS)          →  simulator build + MotifTests + MotifUITests
push to main  →  ios-testflight (macOS)  →  fastlane match (sign) → build IPA
              →  upload to App Store Connect → TestFlight → your iPhone
```

Signing is **shared with Financial Management**: the same Apple team
(`F73L2977Q8`), the same `darianthedy/ios-certificates` match repo, the same
App Store Connect API key. Only the bundle ID, the app record and this repo's
secrets are new.

| File | Purpose |
|---|---|
| `.github/workflows/ios-ci.yml` | PR check: `scripts/ios-verify.sh --ios` on a simulator, plus `npm test` |
| `.github/workflows/ios-testflight.yml` | Runs `fastlane beta` on push to `main` touching `iOS/**` |
| `iOS/Motif/fastlane/Fastfile` | `beta` (sign + build + upload) and `test` lanes |
| `iOS/Motif/fastlane/Appfile` | App identifier / team |
| `iOS/Motif/fastlane/Matchfile` | Where signing assets are stored |
| `iOS/Motif/Gemfile` | Pins fastlane |

---

## One-time setup

### 1. Register the bundle ID
[developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
→ **+** → App IDs → App → explicit bundle ID `com.dthedy.Motif`. No extra
capabilities are needed.

### 2. Create the app record
[App Store Connect → Apps](https://appstoreconnect.apple.com) → **+** → **New App**,
bundle ID `com.dthedy.Motif`. App Store names are global, so "Motif" may be
taken — pick e.g. "Motif Chess". The name on the home screen stays "Motif"
(`CFBundleDisplayName`).

### 3. Add the GitHub secrets
In **this** repo → Settings → Secrets and variables → **Actions** → New secret.
Copy the values from Financial Management (you can't read secrets back from
GitHub, so take them from wherever you saved them):

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | the API Key ID |
| `ASC_ISSUER_ID` | the API Issuer ID |
| `ASC_KEY_CONTENT` | base64 of the `.p8`, **single line** |
| `MATCH_GIT_URL` | `https://github.com/darianthedy/ios-certificates.git` |
| `MATCH_PASSWORD` | the match passphrase |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 of `user:PAT`, **single line** |

`VITE_NEON_BASE_URL` already exists (the Pages deploy uses it); the TestFlight
lane passes it as `NEON_BASE_URL` and **fails** if it is missing, because an
empty value builds the in-memory dev backend.

If you need to re-encode a value in WSL, use `-w0` — GNU `base64` wraps at 76
columns and a multi-line secret breaks the build:
```bash
base64 -w0 AuthKey_XXXXXXXXXX.p8
echo -n "darianthedy:ghp_YOUR_PAT" | base64 -w0
```

### 4. First run
Add a repo **Variable** `MATCH_CREATE_CERTS = true` (Settings → Secrets and
variables → Actions → **Variables**), then **Actions** → **iOS TestFlight** →
**Run workflow**. match reuses the existing distribution certificate and
creates the App Store profile for the new bundle ID.

**After it succeeds, delete `MATCH_CREATE_CERTS`.** Every later run stays
read-only and reuses the stored profile.

### 5. Install on your iPhone
1. Install **TestFlight** from the App Store.
2. App Store Connect → the app → TestFlight → add yourself as an
   **Internal Tester**.
3. Accept the invite in TestFlight and install. Later uploads arrive as
   updates.

---

## Gotchas (all already handled — listed so a failure is recognisable)
- **`A libcurl function was given a bad argument`** when match clones = a
  multi-line `MATCH_GIT_BASIC_AUTHORIZATION`. Re-encode with `-w0`.
- **`No code signing identity found ... readonly`** on the first run =
  `MATCH_CREATE_CERTS` isn't set. `setup_ci` forces read-only otherwise.
- **`No signing certificate "iOS Development" found`** = the app target needs
  `CODE_SIGN_IDENTITY = Apple Distribution`; the Fastfile sets it.
- **`... does not support provisioning profiles`** for ChessKit = signing was
  applied globally. The Fastfile scopes it to the app target with
  `update_code_signing_settings`.
- **`Missing required icon file ... (90022)`** = no 1024×1024 opaque icon.
  `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is one
  (regenerate with `scripts/ios-icon.swift`).
- **Xcode version**: deployment target iOS 26.1 needs Xcode 26, hence
  `macos-26`. If GitHub renames the image, update `runs-on` in both workflows.
- **Simulator**: `ios-ci` picks one with `scripts/ios-simulator.sh`, so a
  renamed iPhone on the runner image doesn't break it.
- The committed shared scheme
  (`Motif.xcodeproj/xcshareddata/xcschemes/Motif.xcscheme`) is what lets CI
  find the `Motif` scheme — don't delete it.

## Cost
The repo is public, so GitHub macOS minutes are free.
