# Shipping the iOS app to TestFlight (from the Mac Mini)

The app is built, signed (fastlane match) and uploaded to TestFlight **locally
on the Mac Mini**. This replaced the old `ios-testflight.yml` GitHub workflow.

```bash
scripts/ios-release/testflight.sh   # fetch nets → bundle exec fastlane beta → restore the pbxproj
```

Run it from whatever branch you're testing. The build appears in **App Store
Connect → TestFlight** a few minutes after the upload, once Apple finishes
processing. Build numbers are `YYYYMMDDHHMM` timestamps (the Fastfile's fallback
when `BUILD_NUMBER` is unset), always higher than the old CI run numbers.

## Configuration (outside git)

- **Signing:** shared by every app on this Mac (same team `F73L2977Q8` and
  `darianthedy/ios-certificates` match repo as Financial Management). One Apple
  Distribution cert, one App Store Connect API key, one match password, all described
  in `~/.config/ios-signing/README.md`. The Fastfile loads
  `~/.config/ios-signing/signing.env` by itself. Profile:
  `ios-signing AppStore com.dthedy.Motif`.
- **Neon:** the repo's git-ignored `.env` holds `VITE_NEON_BASE_URL`; the Fastfile
  passes it as `NEON_BASE_URL` and **fails** if it is missing, because an empty value
  builds the in-memory dev backend.

| File | Purpose |
|---|---|
| `scripts/ios-release/testflight.sh` | Runs `fastlane beta` and cleans up |
| `iOS/Motif/fastlane/Fastfile` | `beta` (sign + build + upload) and `test` lanes |
| `iOS/Motif/fastlane/Appfile` | App identifier / team |
| `iOS/Motif/fastlane/Matchfile` | Where signing assets are stored |
| `iOS/Motif/Gemfile` | Pins fastlane |

## Install on your iPhone
1. Install **TestFlight** from the App Store.
2. App Store Connect → the app → TestFlight → add yourself as an
   **Internal Tester**.
3. Accept the invite in TestFlight and install. Later uploads arrive as
   updates.

## Gotchas (all already handled — listed so a failure is recognisable)
- **`No signing certificate "iOS Development" found`** = the app target needs
  `CODE_SIGN_IDENTITY = Apple Distribution`; the Fastfile sets it.
- **`... does not support provisioning profiles`** for ChessKit = signing was
  applied globally. The Fastfile scopes it to the app target with
  `update_code_signing_settings` (which edits the pbxproj; the script restores it).
- **`Missing required icon file ... (90022)`** = no 1024×1024 opaque icon.
  `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is one
  (regenerate with `scripts/ios-icon.swift`).
- **Missing NNUE net** = the lane's `fetch-nnue.sh --check-ipa` refuses to upload an
  IPA without the Stockfish nets; the script fetches them first.
- The committed shared scheme
  (`Motif.xcodeproj/xcshareddata/xcschemes/Motif.xcscheme`) is what lets fastlane
  find the `Motif` scheme — don't delete it.
