# motif — notes for Claude

## iOS builds are local (since 2026-11-14)
- We work on a **Mac Mini** with Xcode 27.2 and iOS 27.2 simulators (incl. iPhone Duo).
  Build, test, screenshot and upload the iOS app **here** — see `iOS/README-Mac.md`.
- Do **not** use GitHub Actions macOS runners (`ios-ci`, `ios-testflight`,
  `ios-duo-capture`) or any other external build service. Where a plan or prompt says
  "CI is the compiler" / "`ios-ci` green", read it as `scripts/ios-verify.sh` green locally.
- "No Mac / WSL2" statements in the plans are history.
