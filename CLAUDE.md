# motif — notes for Claude

## iOS builds are local (since 2026-11-14)
- We work on a **Mac Mini** with Xcode 27.2 and iOS 27.2 simulators (incl. iPhone Duo).
  Build, test, screenshot and upload the iOS app **here** — see `iOS/README-Mac.md`.
- Where a plan or prompt says "CI is the compiler" / "`ios-ci` green", read it as
  `scripts/ios-verify.sh` green locally.
- Workflows left on GitHub: `web-ci.yml` (every PR), `web-pages-deploy.yml` (push to
  `main`) and `ios-ci.yml` (nightly full iOS suite, or the `full-ui` PR label). The iOS
  PR check is the pre-push hook (`.githooks/pre-push`; enable with
  `git config core.hooksPath .githooks`), TestFlight is `scripts/ios-release/testflight.sh`.
- "No Mac / WSL2" statements in the plans are history.
